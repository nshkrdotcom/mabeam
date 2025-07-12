# Test Fix #5: Concurrent Agent Operations Race Conditions

**Test File:** `test/mabeam_integration_test.exs:190-234`  
**Library Code:** Multiple GenServer modules (Registry, Agent.Server, EventBus)  
**Risk Level:** ⚠️ **MEDIUM - Race Conditions & Data Corruption**  
**Bug Probability:** **70%** - GenServer concurrent access patterns with potential race conditions

## What This Will Uncover

### Primary Issues Expected
1. **Registry Race Conditions** - Concurrent register/unregister operations causing corruption
2. **Agent Server Deadlocks** - Multiple clients causing GenServer bottlenecks  
3. **Event Ordering Issues** - Concurrent events arriving out of sequence
4. **State Corruption** - Simultaneous updates causing lost or corrupted data

### Code Analysis Reveals Concurrency Vulnerabilities

The MABEAM system has multiple GenServers that can be accessed concurrently:

```elixir
# Registry operations
Registry.register(agent, pid)     # GenServer.call
Registry.get_agent(agent_id)      # GenServer.call  
Registry.unregister(agent_id)     # GenServer.call

# Agent.Server operations  
Agent.Server.update_agent(pid, fn) # GenServer.call
Agent.Server.execute_action(pid, action, params) # GenServer.call

# EventBus operations
EventBus.subscribe(event_type)    # GenServer.call
EventBus.emit(event_type, data)   # GenServer.cast (async!)
```

**The Problem:** These operations can interleave in dangerous ways, causing:
- Agent registration while being unregistered
- State updates during action execution
- Event emission during subscriber cleanup

## Specific Bugs That Will Be Revealed

### Bug #1: Registry Concurrent Registration Race 🚨
**Severity:** HIGH  
**Prediction:** **DATA CORRUPTION** during simultaneous register/unregister

**The Problem:**
- Thread A calls `Registry.register(agent, pid)`
- Thread B calls `Registry.unregister(agent.id)` simultaneously  
- Registry state becomes inconsistent (agent in registrations but not indices)

**What Will Happen:** Our test will reveal:
```elixir
# Concurrent registration/unregistration
Task.async(fn -> Registry.register(agent, pid) end)
Task.async(fn -> Registry.unregister(agent.id) end)
# Result: Registry corruption, inconsistent indices
```

### Bug #2: Agent Server Update Conflicts 🔥
**Severity:** HIGH  
**Prediction:** **LOST UPDATES** during concurrent modifications

**The Problem:**
- Multiple clients call `Agent.Server.update_agent(pid, fn)` simultaneously
- GenServer processes them sequentially, but functions see stale state
- Last-write-wins scenario causes lost updates

**What Will Happen:**
```elixir
# Two clients increment counter simultaneously
Task.async(fn -> Agent.Server.update_agent(pid, fn agent -> 
  %{agent | state: %{counter: agent.state.counter + 1}} 
end) end)
Task.async(fn -> Agent.Server.update_agent(pid, fn agent ->
  %{agent | state: %{counter: agent.state.counter + 1}}
end) end)
# Expected: counter + 2, Actual: counter + 1 (lost update)
```

### Bug #3: Event Emission Race Conditions ⚠️
**Severity:** MEDIUM  
**Prediction:** **OUT-OF-ORDER EVENTS** and timing issues

**The Problem:**
- `EventBus.emit/2` is async (GenServer.cast)
- Multiple events emitted rapidly might arrive out of order
- Events might be emitted during subscriber cleanup

**What Will Happen:**
- Events arrive in wrong order
- Events sent to processes that just unsubscribed
- Event history becomes inconsistent

### Bug #4: GenServer Queue Saturation 🚨
**Severity:** HIGH  
**Prediction:** **SYSTEM SLOWDOWN** under concurrent load

**The Problem:**
- All operations go through single GenServer processes
- High concurrency causes message queue buildup
- System becomes unresponsive under load

## How We'll Make the Test Robust

### Current Inadequate Test
```elixir
test "registry consistency under load" do
  # Creates agents sequentially, doesn't test concurrency
  agents = create_multiple_agents(100)
  assert length(Registry.list_all()) == 100
  # ❌ USELESS: No actual concurrent operations
end
```

### Comprehensive Concurrency Test That Will Reveal Race Conditions
```elixir
test "system handles high concurrency without data corruption or deadlocks" do
  # TEST 1: Concurrent registry operations
  test_concurrent_registry_operations()
  
  # TEST 2: Concurrent agent updates
  test_concurrent_agent_updates()
  
  # TEST 3: Event system under concurrent load
  test_concurrent_event_operations()
  
  # TEST 4: Cross-component concurrency
  test_cross_component_concurrency()
  
  # TEST 5: System performance under load
  test_system_performance_under_concurrency()
end

defp test_concurrent_registry_operations do
  # Create base agents for testing
  base_agents = for i <- 1..10 do
    {:ok, agent, pid} = create_test_agent(:demo, 
      name: String.to_atom("base_agent_#{i}"))
    {agent, pid}
  end
  
  # TEST: Concurrent register/unregister operations
  stress_tasks = for i <- 1..50 do
    Task.async(fn ->
      case rem(i, 3) do
        0 -> 
          # Register new agent
          {:ok, agent, pid} = create_test_agent(:stress_test,
            name: String.to_atom("stress_agent_#{i}"))
          {:register, agent.id, pid}
          
        1 ->
          # Unregister existing agent
          {agent, pid} = Enum.random(base_agents)
          Registry.unregister(agent.id)
          {:unregister, agent.id}
          
        2 ->
          # Get agent (read operation)
          {agent, _pid} = Enum.random(base_agents)
          result = Registry.get_agent(agent.id)
          {:get, agent.id, result}
      end
    end)
  end
  
  # Wait for all operations to complete
  results = Enum.map(stress_tasks, &Task.await(&1, 10_000))
  
  # CRITICAL: Verify registry state consistency after concurrent operations
  verify_registry_consistency_after_concurrency()
  
  # Verify no operations failed due to race conditions
  failures = Enum.filter(results, fn
    {:register, _id, _pid} -> false
    {:unregister, _id} -> false  
    {:get, _id, {:ok, _}} -> false
    {:get, _id, {:error, :not_found}} -> false
    _ -> true  # Any other result is a failure
  end)
  
  assert failures == [], "Race conditions caused operation failures: #{inspect(failures)}"
end

defp test_concurrent_agent_updates do
  {:ok, agent, pid} = create_test_agent(:demo, 
    initial_state: %{counter: 0, data: []})
  
  # Launch 100 concurrent update operations
  update_tasks = for i <- 1..100 do
    Task.async(fn ->
      case rem(i, 4) do
        0 ->
          # Increment counter
          Agent.Server.update_agent(pid, fn agent ->
            current = Map.get(agent.state, :counter, 0)
            put_in(agent.state.counter, current + 1)
          end)
          
        1 ->
          # Add to data list
          Agent.Server.update_agent(pid, fn agent ->
            current = Map.get(agent.state, :data, [])
            put_in(agent.state.data, [i | current])
          end)
          
        2 ->
          # Execute action
          Agent.Server.execute_action(pid, :ping, %{source: i})
          
        3 ->
          # Get current state (read operation)
          Agent.Server.get_agent(pid)
      end
    end)
  end
  
  # Wait for all updates
  results = Enum.map(update_tasks, &Task.await(&1, 5_000))
  
  # CRITICAL: Verify final state consistency
  {:ok, final_agent} = Agent.Server.get_agent(pid)
  
  # Check for lost updates (WILL LIKELY FAIL)
  final_counter = Map.get(final_agent.state, :counter, 0)
  expected_increments = 25  # 100/4 operations were increments
  
  assert final_counter == expected_increments,
    "Lost updates detected - counter: #{final_counter}, expected: #{expected_increments}"
  
  # Check data list integrity
  final_data = Map.get(final_agent.state, :data, [])
  expected_data_items = 25  # 100/4 operations were data additions
  
  assert length(final_data) == expected_data_items,
    "Lost data updates - data items: #{length(final_data)}, expected: #{expected_data_items}"
  
  # Verify no duplicate data (indicates race conditions)
  unique_data = Enum.uniq(final_data)
  assert length(unique_data) == length(final_data),
    "Duplicate data detected - race condition in list updates"
end

defp test_concurrent_event_operations do
  # Create multiple subscribers
  subscribers = for i <- 1..20 do
    {:ok, subscriber} = GenServer.start_link(TestEventSubscriber, [])
    EventBus.subscribe("stress_test_event", subscriber)
    subscriber
  end
  
  # Emit events rapidly from multiple processes
  emission_tasks = for i <- 1..100 do
    Task.async(fn ->
      EventBus.emit("stress_test_event", %{id: i, timestamp: System.monotonic_time()})
    end)
  end
  
  # Wait for all emissions
  Enum.each(emission_tasks, &Task.await(&1, 5_000))
  
  # Give events time to propagate
  :timer.sleep(1000)
  
  # Verify all subscribers received all events
  for subscriber <- subscribers do
    events = get_received_events(subscriber)
    
    # Should receive all 100 events (MIGHT FAIL due to race conditions)
    assert length(events) == 100,
      "Subscriber #{inspect(subscriber)} received #{length(events)} events, expected 100"
    
    # Events should be unique (no duplicates from race conditions)  
    event_ids = Enum.map(events, & &1.data.id)
    unique_ids = Enum.uniq(event_ids)
    
    assert length(unique_ids) == length(event_ids),
      "Duplicate events detected - race condition in event delivery"
  end
end

defp test_cross_component_concurrency do
  # Test operations that span multiple components simultaneously
  {:ok, agent, pid} = create_test_agent(:demo)
  
  # Subscribe to agent events
  EventBus.subscribe("action_executed")
  
  mixed_tasks = for i <- 1..50 do
    Task.async(fn ->
      case rem(i, 5) do
        0 ->
          # Registry operation
          Registry.get_agent(agent.id)
          
        1 ->
          # Agent update
          Agent.Server.update_agent(pid, fn a -> 
            put_in(a.state.cross_test, i) 
          end)
          
        2 ->
          # Action execution (triggers events)
          Agent.Server.execute_action(pid, :ping, %{cross_test: i})
          
        3 ->
          # Event emission
          EventBus.emit("cross_test_event", %{source: i})
          
        4 ->
          # Registry unregister/register cycle
          Registry.unregister(agent.id)
          :timer.sleep(1)  # Small delay
          Registry.register(agent, pid)
      end
    end)
  end
  
  # Wait for completion
  Enum.each(mixed_tasks, &Task.await(&1, 10_000))
  
  # CRITICAL: Verify system is still consistent
  verify_cross_component_consistency(agent.id, pid)
end

defp test_system_performance_under_concurrency do
  # Create baseline performance measurement
  baseline_start = System.monotonic_time(:microsecond)
  {:ok, agent, pid} = create_test_agent(:performance_test)
  Registry.get_agent(agent.id)
  Agent.Server.execute_action(pid, :ping, %{})
  baseline_end = System.monotonic_time(:microsecond)
  baseline_time = baseline_end - baseline_start
  
  # Test performance under high concurrency
  concurrent_start = System.monotonic_time(:microsecond)
  
  # Launch many concurrent operations
  concurrent_tasks = for i <- 1..200 do
    Task.async(fn ->
      case rem(i, 3) do
        0 -> Registry.get_agent(agent.id)
        1 -> Agent.Server.get_agent(pid)
        2 -> EventBus.emit("perf_test", %{id: i})
      end
    end)
  end
  
  Enum.each(concurrent_tasks, &Task.await(&1, 15_000))
  concurrent_end = System.monotonic_time(:microsecond)
  concurrent_time = concurrent_end - concurrent_start
  
  # Performance shouldn't degrade too much under concurrency
  per_operation_time = concurrent_time / 200
  performance_ratio = per_operation_time / baseline_time
  
  # CRITICAL: System should remain responsive (MIGHT FAIL)
  assert performance_ratio < 10.0,
    "Performance degraded #{performance_ratio}x under concurrency"
  
  assert per_operation_time < 50_000,  # 50ms max per operation
    "Operations taking #{per_operation_time}μs under concurrency - too slow"
end

# Helper functions
defp verify_registry_consistency_after_concurrency do
  state = :sys.get_state(Registry)
  
  # Every registration should have a monitor
  registration_count = Map.size(state.registrations)
  monitor_count = Map.size(state.monitors)
  
  assert registration_count == monitor_count,
    "Registration/monitor mismatch after concurrency: #{registration_count} vs #{monitor_count}"
  
  # Indices should match registrations
  total_in_indices = state.indices.by_type
    |> Map.values()
    |> Enum.flat_map(&MapSet.to_list/1)
    |> Enum.uniq()
    |> length()
    
  assert total_in_indices == registration_count,
    "Index/registration mismatch: #{total_in_indices} vs #{registration_count}"
end

defp verify_cross_component_consistency(agent_id, pid) do
  # Verify agent exists in Registry
  assert {:ok, registry_agent} = Registry.get_agent(agent_id)
  
  # Verify agent is responsive
  assert {:ok, server_agent} = Agent.Server.get_agent(pid)
  
  # Verify basic consistency
  assert registry_agent.id == server_agent.id,
    "Cross-component inconsistency after concurrent operations"
end

defp get_received_events(subscriber_pid) do
  ref = make_ref()
  send(subscriber_pid, {:get_events, ref, self()})
  
  receive do
    {:events, ^ref, events} -> events
  after
    1000 -> []
  end
end
```

## Expected Test Results

### What Will Break (Predictions)
1. **Lost Updates**: Counter increments will be lost during concurrent updates
2. **Registry Corruption**: Concurrent register/unregister will cause state inconsistency  
3. **Event Duplicates**: Race conditions will cause duplicate or missing events
4. **Performance Degradation**: System will slow down significantly under concurrent load
5. **Deadlocks**: Some operations may timeout due to GenServer queue saturation

### Specific Failure Scenarios
```bash
Lost updates detected - counter: 18, expected: 25

Registration/monitor mismatch after concurrency: 8 vs 12

Subscriber received 97 events, expected 100

Performance degraded 15.2x under concurrency

Operations taking 75000μs under concurrency - too slow
```

### Why This Matters for Production
In production with multiple services and high concurrency:
- **Data Loss**: Lost updates cause inconsistent agent states
- **System Instability**: Race conditions cause unpredictable behavior
- **Performance Issues**: GenServer bottlenecks slow down entire system
- **Event Reliability**: Missing or duplicate events break workflows
- **Scaling Problems**: System doesn't handle increased load gracefully

### Root Cause Analysis
The issues stem from:
- **Single GenServer Bottlenecks**: All operations serialize through single processes
- **Insufficient Locking**: No coordination between related operations
- **Async/Sync Mismatches**: Event emission is async while other operations are sync
- **Missing Optimistic Concurrency**: No version control for updates

## Success Criteria

The test fix is successful when:
1. **No Lost Updates**: All concurrent updates are preserved
2. **State Consistency**: Registry and Agent.Server remain synchronized
3. **Event Reliability**: All events delivered exactly once
4. **Performance Scaling**: Sub-linear performance degradation under load
5. **No Deadlocks**: All operations complete within reasonable time

This test fix will force implementation of:
- Proper concurrency control mechanisms
- Optimistic locking for updates
- Better async/sync coordination
- Performance optimization under load