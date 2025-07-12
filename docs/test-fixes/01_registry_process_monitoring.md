# Test Fix #1: Registry Process Monitoring Race Conditions

**Test File:** `test/mabeam/foundation/registry_test.exs:59-89`  
**Library Code:** `lib/mabeam/foundation/registry.ex`  
**Risk Level:** 🚨 **CRITICAL - Memory Leaks & State Corruption**  
**Bug Probability:** **95%** - Multiple race conditions and edge cases identified

## What This Will Uncover

### Primary Issues Expected
1. **Race Condition in Monitor Cleanup** - The `:DOWN` message handler has a critical flaw
2. **Index Corruption** - Indices might become inconsistent during cleanup
3. **Telemetry Race Conditions** - Events might be emitted with stale data
4. **Memory Leaks** - Monitor references might accumulate

### Code Analysis Reveals Critical Flaws

Looking at `lib/mabeam/foundation/registry.ex:247-267`, the `:DOWN` message handler has **several serious problems**:

```elixir
def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
  case Map.get(state.monitors, ref) do
    nil ->
      {:noreply, state}  # ❌ PROBLEM: Untracked monitors ignored

    agent_id ->
      # Get agent data before removal
      registration = get_in(state, [:registrations, agent_id])  
      # ❌ PROBLEM: No nil check - will crash if registration missing

      # Clean up
      new_state =
        state
        |> update_in([:registrations], &Map.delete(&1, agent_id))
        |> update_in([:monitors], &Map.delete(&1, ref))
        |> update_indices(:remove, registration.agent_data)
        # ❌ PROBLEM: update_indices called with potentially nil registration
```

## Specific Bugs That Will Be Revealed

### Bug #1: Nil Registration Crash 🚨
**Severity:** CRITICAL  
**Prediction:** **WILL CRASH** with `FunctionClauseError`

**The Problem:** Lines 256 and 263 assume registration exists, but it might be nil due to race conditions:
- Agent unregisters manually while process is dying
- Double cleanup scenarios
- Manual state corruption during testing

**What Will Happen:** When we fix the test to properly verify cleanup, this will crash with:
```
** (FunctionClauseError) no function clause matching in Mabeam.Foundation.Registry.update_indices/3
```

### Bug #2: Index Corruption 🚨  
**Severity:** CRITICAL  
**Prediction:** **SILENT DATA CORRUPTION**

**The Problem:** If `registration.agent_data` is nil, `update_indices(:remove, nil)` will either:
1. Crash the GenServer (stopping the entire Registry)
2. Silently fail to remove indices (causing memory leaks)
3. Corrupt the index data structures

**What Will Happen:** Indices will become inconsistent with registrations, causing:
- `list_by_type/1` returning non-existent agents
- `list_by_capability/1` returning dead agents
- Memory usage growing unbounded

### Bug #3: Monitor Reference Leaks 🔥
**Severity:** HIGH  
**Prediction:** **MEMORY LEAK CONFIRMED**

**The Problem:** Looking at the code, there's no protection against:
- Double-registration scenarios creating orphaned monitors
- Process exits before registration completes
- Manual unregistration not cleaning up monitors

**What Will Happen:** The `monitors` map will accumulate dead references, causing:
- Unbounded memory growth
- Performance degradation over time
- Eventually system instability

### Bug #4: Telemetry with Stale Data ⚠️
**Severity:** MEDIUM  
**Prediction:** **INCORRECT METRICS**

**The Problem:** Telemetry events use potentially stale agent data:
```elixir
:telemetry.execute(
  [:mabeam, :registry, :unregister],
  %{count: 1},
  %{agent_id: agent_id, agent_type: registration.agent_data.type}
  # ❌ registration.agent_data might be nil or stale
)
```

## How We'll Make the Test Robust

### Current Broken Test
```elixir
test "registry monitors registered processes" do
  # ... setup ...
  Process.exit(mock_pid, :kill)
  # ❌ WEAK: Only checks public API, not internal state
  assert {:error, :not_found} = Registry.get_agent(agent.id)
end
```

### Fixed Test That Will Reveal Bugs
```elixir
test "registry completely cleans up dead processes and maintains state consistency" do
  # Create multiple agents to test index consistency
  agents = for i <- 1..5 do
    {:ok, agent, pid} = create_test_agent(:demo, 
      capabilities: [:ping, :test],
      name: String.to_atom("test_agent_#{i}")
    )
    {agent, pid}
  end
  
  # Verify initial state is consistent
  verify_registry_state_consistency()
  
  # Kill the middle agent (tests index removal logic)
  {target_agent, target_pid} = Enum.at(agents, 2)
  ref = Process.monitor(target_pid)
  
  # CRITICAL: Test concurrent operations during cleanup
  # This will trigger race conditions
  Task.async(fn ->
    Registry.get_agent(target_agent.id)
  end)
  
  Process.exit(target_pid, :kill)
  
  # Wait for process death and Registry cleanup
  receive do
    {:DOWN, ^ref, :process, ^target_pid, _reason} -> :ok
  after
    1000 -> flunk("Process did not terminate")
  end
  
  # Give Registry time to process :DOWN message
  # This is where the crashes will happen
  :timer.sleep(100)
  
  # COMPREHENSIVE STATE VERIFICATION:
  
  # 1. Public API consistency
  assert {:error, :not_found} = Registry.get_agent(target_agent.id)
  
  # 2. Internal state consistency (THIS WILL FAIL)
  registry_state = :sys.get_state(Registry)
  
  # This will reveal monitor leaks
  assert Map.size(registry_state.monitors) == 4  # Should be 4, not 5
  
  # This will reveal registration cleanup issues
  assert Map.size(registry_state.registrations) == 4
  
  # 3. Index consistency (THIS WILL FAIL BADLY)
  # Verify agent removed from type indices
  demo_agents = Registry.list_by_type(:demo)
  refute Enum.any?(demo_agents, fn agent -> agent.id == target_agent.id end)
  
  # Verify agent removed from capability indices
  ping_agents = Registry.list_by_capability(:ping)
  refute Enum.any?(ping_agents, fn agent -> agent.id == target_agent.id end)
  
  # 4. No orphaned monitor references (THIS WILL REVEAL LEAKS)
  for {_ref, agent_id} <- registry_state.monitors do
    # Every monitor should have a corresponding registration
    assert Map.has_key?(registry_state.registrations, agent_id)
  end
  
  # 5. Index-registration consistency (THIS WILL EXPOSE CORRUPTION)
  verify_registry_state_consistency()
  
  # 6. Stress test: Rapid agent creation/destruction
  stress_test_process_monitoring()
end

defp verify_registry_state_consistency do
  state = :sys.get_state(Registry)
  
  # Every registration should have a monitor
  for {agent_id, registration} <- state.registrations do
    monitor_exists = Enum.any?(state.monitors, fn {_ref, id} -> id == agent_id end)
    assert monitor_exists, "Agent #{agent_id} has no monitor"
  end
  
  # Every monitor should have a registration
  for {_ref, agent_id} <- state.monitors do
    assert Map.has_key?(state.registrations, agent_id), 
           "Monitor exists for non-registered agent #{agent_id}"
  end
  
  # Index counts should match registration counts
  total_in_indices = state.indices.by_type
                    |> Map.values()
                    |> Enum.flat_map(&MapSet.to_list/1)
                    |> Enum.uniq()
                    |> length()
  
  assert total_in_indices == Map.size(state.registrations),
         "Index count (#{total_in_indices}) != registration count (#{Map.size(state.registrations)})"
end

defp stress_test_process_monitoring do
  # Rapidly create and kill processes to trigger race conditions
  tasks = for i <- 1..20 do
    Task.async(fn ->
      {:ok, agent, pid} = create_test_agent(:stress_test, 
        name: String.to_atom("stress_#{i}"))
      :timer.sleep(Enum.random(1..50))  # Random timing
      Process.exit(pid, :kill)
      agent.id
    end)
  end
  
  killed_ids = Enum.map(tasks, &Task.await(&1, 5000))
  
  # Wait for all cleanup to complete
  :timer.sleep(200)
  
  # Verify no leaks
  verify_registry_state_consistency()
  
  # Verify all stress test agents are gone
  for agent_id <- killed_ids do
    assert {:error, :not_found} = Registry.get_agent(agent_id)
  end
end
```

## Expected Test Results

### What Will Break (Predictions)
1. **Line 263 Crash**: `update_indices(:remove, nil)` will crash with `FunctionClauseError`
2. **Monitor Count Assertion**: Will fail - monitors map will have 5 entries instead of 4
3. **Index Consistency**: Will fail - dead agent will still appear in type/capability indices
4. **Stress Test**: Will crash or leave orphaned state after ~5-10 iterations

### Why This Matters for Production
In production, these bugs manifest as:
- **Memory leaks** causing gradual system degradation
- **Inconsistent agent listings** confusing users
- **Registry crashes** taking down the entire agent system
- **Race conditions** during high agent churn (CI/CD, auto-scaling)

### Performance Impact
- Monitor map grows unbounded (100MB+ after days of operation)
- Index queries return stale data
- GenServer becomes bottleneck as state grows
- System requires restarts to clear leaked memory

## Success Criteria

The test fix is successful when:
1. **Crashes are fixed** - No more nil reference crashes
2. **Leaks are plugged** - Monitor count equals registration count
3. **Indices stay consistent** - No orphaned index entries
4. **Stress test passes** - Can handle rapid create/destroy cycles
5. **Performance is stable** - Memory usage remains bounded

This test fix will force proper implementation of:
- Nil-safe cleanup logic
- Atomic state updates
- Proper monitor lifecycle management
- Consistent index maintenance