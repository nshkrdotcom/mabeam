# Test Fix #3: Agent Lifecycle State Consistency

**Test File:** `test/mabeam/demo_agent_test.exs` (multiple locations)  
**Library Code:** `lib/mabeam/foundation/agent/server.ex`, `lib/mabeam/foundation/registry.ex`  
**Risk Level:** 🔥 **HIGH - State Drift & Data Corruption**  
**Bug Probability:** **85%** - State synchronization issues and race conditions identified

## What This Will Uncover

### Primary Issues Expected
1. **State Drift** - Registry and Agent.Server maintaining different agent states
2. **Missing Registry Updates** - Agent.Server state changes not reflected in Registry
3. **Race Conditions** - Concurrent updates causing state corruption
4. **Lifecycle Event Failures** - State changes not emitting proper events

### Code Analysis Reveals Critical Synchronization Gap

Looking at `lib/mabeam/foundation/agent/server.ex:115-144`, the agent update mechanisms have a **fundamental design flaw**:

```elixir
def handle_call({:update_agent, update_fn}, _from, state) do
  try do
    updated_agent = update_fn.(state.agent)
    new_state = %{state | agent: updated_agent}
    {:reply, {:ok, updated_agent}, new_state}
    # ❌ CRITICAL FLAW: Registry is NEVER updated!
  rescue
    error ->
      {:reply, {:error, error}, state}
  end
end

def handle_call({:execute_action, action, params}, _from, state) do
  case agent_module.handle_action(state.agent, action, params) do
    {:ok, updated_agent, result} ->
      new_state = %{state | agent: updated_agent}
      # ❌ SAME FLAW: Registry has stale data!
      
      # Emit action executed event  
      EventBus.emit("action_executed", %{
        agent_id: state.agent.id,  # ❌ Using OLD agent state!
        # ...
      })
```

## Specific Bugs That Will Be Revealed

### Bug #1: State Drift Between Components 🚨
**Severity:** CRITICAL  
**Prediction:** **GUARANTEED FAILURE** - No synchronization exists

**The Problem:** 
- Agent.Server updates its internal agent state
- Registry keeps the original agent state from registration
- No mechanism exists to sync Registry with Agent.Server updates
- Two sources of truth that diverge immediately

**What Will Happen:** Our test will reveal:
```elixir
{:ok, registry_agent} = Registry.get_agent(agent_id)
{:ok, server_agent} = Agent.Server.get_agent(pid)

# WILL FAIL: Different states
assert registry_agent.state == server_agent.state  # ❌ FAIL
assert registry_agent.updated_at == server_agent.updated_at  # ❌ FAIL
```

### Bug #2: Stale Registry Data 🔥
**Severity:** HIGH  
**Prediction:** **REGISTRY SHOWS OLD DATA**

**The Problem:**
- Registry.get_agent/1 returns outdated agent information
- Agent listing functions show stale capabilities, state, lifecycle
- UI and API show incorrect agent status

**What Will Happen:** 
- Agent performs action and changes state
- Registry still shows pre-action state
- Agent appears to have different capabilities than it actually has
- Users see inconsistent agent information

### Bug #3: Event Data Inconsistency ⚠️
**Severity:** MEDIUM  
**Prediction:** **EVENTS CONTAIN STALE DATA**

**The Problem:** Line 140-144 emits events using potentially stale agent data:
```elixir
EventBus.emit("action_executed", %{
  agent_id: state.agent.id,  # This might be correct
  action: action,
  params: params,
  result: result  # But agent metadata/state in events is stale
})
```

**What Will Happen:**
- Event listeners receive outdated agent information
- Monitoring systems show incorrect agent states
- Audit trails contain inconsistent data

### Bug #4: Concurrent Update Race Conditions 🚨
**Severity:** CRITICAL  
**Prediction:** **DATA CORRUPTION** during concurrent operations

**The Problem:**
- Multiple clients can call update_agent simultaneously
- No coordination between Agent.Server and Registry updates
- Last-write-wins scenarios cause data loss

**What Will Happen:**
- Concurrent updates will overwrite each other
- Agent state becomes corrupted
- Lost updates with no error indication

## How We'll Make the Test Robust

### Current Missing Test Coverage
```elixir
# NO TESTS EXIST for state consistency between components
# Agent tests only verify Agent.Server behavior in isolation
# Registry tests only verify Registry behavior in isolation
# ❌ ZERO integration testing of state synchronization
```

### Comprehensive Test That Will Reveal State Drift
```elixir
test "agent state consistency maintained between Registry and Agent.Server" do
  {:ok, agent, pid} = create_test_agent(:demo, 
    capabilities: [:ping, :increment],
    initial_state: %{counter: 0}
  )
  
  # BASELINE: Verify initial consistency
  verify_state_consistency(agent.id, pid, "initial state")
  
  # TEST 1: Simple state update
  update_fn = fn agent -> 
    %{agent | state: Map.put(agent.state, :counter, 42)} 
  end
  
  {:ok, updated_agent} = Agent.Server.update_agent(pid, update_fn)
  
  # CRITICAL TEST: Registry should reflect the update (WILL FAIL)
  verify_state_consistency(agent.id, pid, "after simple update")
  
  # Verify specific field consistency
  {:ok, registry_agent} = Registry.get_agent(agent.id)
  assert registry_agent.state.counter == 42,
    "Registry shows counter=#{registry_agent.state.counter}, should be 42"
  
  # TEST 2: Action execution updates
  {:ok, action_result} = Agent.Server.execute_action(pid, :increment, %{amount: 10})
  
  # CRITICAL TEST: Both components should show incremented state (WILL FAIL)
  verify_state_consistency(agent.id, pid, "after action execution")
  
  {:ok, registry_agent} = Registry.get_agent(agent.id)
  {:ok, server_agent} = Agent.Server.get_agent(pid)
  
  expected_counter = 52  # 42 + 10
  assert registry_agent.state.counter == expected_counter,
    "Registry counter=#{registry_agent.state.counter}, expected #{expected_counter}"
  assert server_agent.state.counter == expected_counter,
    "Server counter=#{server_agent.state.counter}, expected #{expected_counter}"
  
  # TEST 3: Concurrent updates (WILL REVEAL RACE CONDITIONS)
  test_concurrent_state_updates(agent.id, pid)
  
  # TEST 4: Capability changes
  test_capability_consistency(agent.id, pid)
  
  # TEST 5: Lifecycle state consistency
  test_lifecycle_consistency(agent.id, pid)
end

defp verify_state_consistency(agent_id, pid, context) do
  {:ok, registry_agent} = Registry.get_agent(agent_id)
  {:ok, server_agent} = Agent.Server.get_agent(pid)
  
  # COMPREHENSIVE CONSISTENCY CHECKS (WILL FAIL)
  
  # 1. Core agent data
  assert registry_agent.id == server_agent.id,
    "#{context}: Agent ID mismatch - Registry: #{registry_agent.id}, Server: #{server_agent.id}"
  
  assert registry_agent.type == server_agent.type,
    "#{context}: Agent type mismatch - Registry: #{registry_agent.type}, Server: #{server_agent.type}"
  
  # 2. State consistency (CRITICAL - WILL FAIL)
  assert registry_agent.state == server_agent.state,
    "#{context}: State mismatch - Registry: #{inspect(registry_agent.state)}, Server: #{inspect(server_agent.state)}"
  
  # 3. Capability consistency
  assert registry_agent.capabilities == server_agent.capabilities,
    "#{context}: Capabilities mismatch - Registry: #{inspect(registry_agent.capabilities)}, Server: #{inspect(server_agent.capabilities)}"
  
  # 4. Lifecycle consistency
  assert registry_agent.lifecycle == server_agent.lifecycle,
    "#{context}: Lifecycle mismatch - Registry: #{registry_agent.lifecycle}, Server: #{server_agent.lifecycle}"
  
  # 5. Timestamp consistency (within reasonable window)
  time_diff = DateTime.diff(registry_agent.updated_at, server_agent.updated_at, :millisecond)
  assert abs(time_diff) < 1000,
    "#{context}: Timestamp drift #{time_diff}ms - Registry: #{registry_agent.updated_at}, Server: #{server_agent.updated_at}"
  
  # 6. Metadata consistency
  assert registry_agent.metadata == server_agent.metadata,
    "#{context}: Metadata mismatch - Registry: #{inspect(registry_agent.metadata)}, Server: #{inspect(server_agent.metadata)}"
end

defp test_concurrent_state_updates(agent_id, pid) do
  # Launch 20 concurrent update operations
  tasks = for i <- 1..20 do
    Task.async(fn ->
      update_fn = fn agent ->
        current_counter = Map.get(agent.state, :counter, 0)
        %{agent | state: Map.put(agent.state, :counter, current_counter + i)}
      end
      
      Agent.Server.update_agent(pid, update_fn)
    end)
  end
  
  # Wait for all updates to complete
  results = Enum.map(tasks, &Task.await(&1, 5000))
  
  # Verify all updates succeeded
  for result <- results do
    assert match?({:ok, _}, result), "Concurrent update failed: #{inspect(result)}"
  end
  
  # CRITICAL: Verify final state consistency (WILL LIKELY FAIL)
  verify_state_consistency(agent_id, pid, "after concurrent updates")
  
  # Check for lost updates
  {:ok, final_agent} = Agent.Server.get_agent(pid)
  final_counter = Map.get(final_agent.state, :counter, 0)
  
  # The exact final value depends on race conditions, but should be reasonable
  assert final_counter >= 52,  # Original 52 + at least some increments
    "Lost updates detected - final counter: #{final_counter}"
  
  assert final_counter <= 52 + 210,  # Original + sum(1..20) = 210
    "Impossible counter value - race condition: #{final_counter}"
end

defp test_capability_consistency(agent_id, pid) do
  # Update capabilities via Agent.Server
  update_fn = fn agent ->
    %{agent | capabilities: [:ping, :increment, :new_capability]}
  end
  
  {:ok, _} = Agent.Server.update_agent(pid, update_fn)
  
  # Verify Registry reflects capability changes (WILL FAIL)
  {:ok, registry_agent} = Registry.get_agent(agent_id)
  assert :new_capability in registry_agent.capabilities,
    "Registry missing new capability: #{inspect(registry_agent.capabilities)}"
  
  # Verify Registry indices are updated
  agents_with_new_cap = Registry.list_by_capability(:new_capability)
  agent_ids = Enum.map(agents_with_new_cap, & &1.id)
  assert agent_id in agent_ids,
    "Agent not found in capability index for :new_capability"
end

defp test_lifecycle_consistency(agent_id, pid) do
  # Simulate lifecycle state change
  update_fn = fn agent ->
    %{agent | lifecycle: :suspended, updated_at: DateTime.utc_now()}
  end
  
  {:ok, _} = Agent.Server.update_agent(pid, update_fn)
  
  # Verify Registry shows updated lifecycle (WILL FAIL)
  {:ok, registry_agent} = Registry.get_agent(agent_id)
  assert registry_agent.lifecycle == :suspended,
    "Registry lifecycle: #{registry_agent.lifecycle}, expected: :suspended"
end
```

## Expected Test Results

### What Will Break (Predictions)
1. **State Consistency Check**: Will fail immediately after first update
2. **Counter Value Assertions**: Registry will show 0, Server will show 42
3. **Capability Index**: Registry indices won't reflect Agent.Server capability changes
4. **Concurrent Updates**: Will reveal race conditions and lost updates
5. **Timestamp Drift**: Registry timestamps will be hours/days old

### Specific Failure Scenarios
```bash
# Expected test output:
1) Agent state consistency
   test/mabeam/demo_agent_test.exs:XXX
   Assertion with == failed
   code:  assert registry_agent.state == server_agent.state
   left:  %{counter: 0}  # Registry has stale state
   right: %{counter: 42} # Server has current state
   
2) Capability consistency  
   Registry missing new capability: [:ping, :increment]
   
3) Lifecycle consistency
   Registry lifecycle: :active, expected: :suspended
```

### Why This Matters for Production
In production, state drift causes:
- **User Confusion**: UI shows different agent status than reality
- **API Inconsistency**: Different endpoints return different agent data  
- **Monitoring Failures**: Metrics and alerts based on stale data
- **Integration Bugs**: External systems receive inconsistent information
- **Audit Problems**: Event logs contain outdated agent information

### Performance Impact
- Multiple sources of truth require duplicate API calls
- Registry becomes useless for current agent state
- Applications must query Agent.Server directly (doesn't scale)
- Cache invalidation becomes impossible

## Success Criteria

The test fix is successful when:
1. **State Synchronization**: Registry always reflects current Agent.Server state
2. **Atomic Updates**: State changes are atomic across both components
3. **Concurrent Safety**: Multiple updates don't cause corruption
4. **Event Consistency**: Events contain current agent data
5. **Index Accuracy**: Registry indices reflect current capabilities/state

This test fix will force implementation of:
- Proper state synchronization mechanisms
- Atomic update protocols
- Consistent event emission
- Race condition prevention