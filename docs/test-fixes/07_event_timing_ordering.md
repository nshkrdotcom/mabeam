# Test Fix #7: Event Emission Timing and Ordering

**Test File:** `test/mabeam/demo_agent_test.exs:166-255`  
**Library Code:** `lib/mabeam/foundation/communication/event_bus.ex`, Agent action execution  
**Risk Level:** ⚠️ **MEDIUM - Event Ordering & Timing Issues**  
**Bug Probability:** **60%** - Async event system with potential ordering and timing problems

## What This Will Uncover

### Primary Issues Expected
1. **Event Ordering Violations** - Events arriving out of sequence
2. **Event Timing Inconsistencies** - Events emitted at wrong lifecycle points
3. **Race Conditions in Event Delivery** - Events lost or duplicated during concurrent operations
4. **Event-Action Synchronization Issues** - Events emitted before actions complete

### Code Analysis Reveals Timing and Ordering Vulnerabilities

Looking at the event emission patterns in `agent/server.ex` and the async nature of `EventBus.emit/2`:

```elixir
# In agent/server.ex:127-144
case agent_module.handle_action(state.agent, action, params) do
  {:ok, updated_agent, result} ->
    new_state = %{state | agent: updated_agent}
    
    # ❌ TIMING ISSUE: Event emitted BEFORE state update confirmed
    EventBus.emit("action_executed", %{
      agent_id: state.agent.id,
      action: action,
      result: result
    })
    
    {:reply, {:ok, result}, new_state}
```

**The Problem:** Events are emitted asynchronously via `GenServer.cast`, which means:
- Events might be delivered before the action actually completes
- Multiple events from the same agent might arrive out of order
- Event data might reflect stale state
- No guarantee of event delivery ordering

## Specific Bugs That Will Be Revealed

### Bug #1: Action-Event Timing Race Condition 🚨
**Severity:** HIGH  
**Prediction:** **EVENTS ARRIVE BEFORE ACTIONS COMPLETE**

**The Problem:**
- `EventBus.emit/2` is async (GenServer.cast)
- Action response is returned immediately after emit
- Events might be processed before action fully completes
- Event listeners see inconsistent state

**What Will Happen:** Our test will reveal:
```elixir
# Start action
Agent.Server.execute_action(pid, :increment, %{amount: 5})

# Event arrives with old state
receive do
  {:event, %{type: "action_executed", data: %{result: result}}} ->
    # Check agent state immediately
    {:ok, agent} = Agent.Server.get_agent(pid)
    # State might not reflect the increment yet!
    assert agent.state.counter == result.new_value  # MIGHT FAIL
end
```

### Bug #2: Event Ordering Violations ⚠️
**Severity:** MEDIUM  
**Prediction:** **EVENTS ARRIVE OUT OF SEQUENCE**

**The Problem:**
- Multiple rapid actions on same agent
- Each action emits event via async cast
- EventBus processes events in arbitrary order
- Event sequence doesn't match action sequence

**What Will Happen:**
```elixir
# Execute actions in sequence
Agent.Server.execute_action(pid, :set_value, %{value: 1})  # Should emit first
Agent.Server.execute_action(pid, :set_value, %{value: 2})  # Should emit second  
Agent.Server.execute_action(pid, :set_value, %{value: 3})  # Should emit third

# Events might arrive as: 2, 1, 3 or any other order
# Listeners can't rely on event order matching action order
```

### Bug #3: Event Data Staleness 🔥
**Severity:** HIGH  
**Prediction:** **EVENTS CONTAIN OUTDATED INFORMATION**

**The Problem:**
- Events are emitted with `state.agent` (old state)
- Action updates agent state but event uses pre-update data
- Event timestamp might not reflect actual completion time

**What Will Happen:**
```elixir
# Event data will be inconsistent with actual agent state
EventBus.emit("action_executed", %{
  agent_id: state.agent.id,           # Correct
  action: action,                     # Correct
  result: result,                     # Correct
  agent_state: state.agent.state      # ❌ STALE - old state!
})
```

### Bug #4: Concurrent Action Event Conflicts ⚠️
**Severity:** MEDIUM  
**Prediction:** **EVENT CONFLICTS** during concurrent operations

**The Problem:**
- Multiple clients execute actions simultaneously
- Events from different actions can interleave
- No way to correlate events with specific action invocations
- Event listeners see confusing event streams

## How We'll Make the Test Robust

### Current Inadequate Test
```elixir
test "emits events during operations" do
  # Complex nested receive blocks that hide timing issues
  receive do
    {:event, _} -> assert true  # Accepts any event
  after 1000 -> flunk("No event")
  end
  # ❌ INADEQUATE: Doesn't test ordering, timing, or data consistency
end
```

### Comprehensive Event Timing Test That Will Reveal Issues
```elixir
test "event emission timing, ordering, and data consistency" do
  # TEST 1: Event-action timing synchronization
  test_event_action_timing()
  
  # TEST 2: Event ordering consistency
  test_event_ordering()
  
  # TEST 3: Event data freshness
  test_event_data_consistency()
  
  # TEST 4: Concurrent event handling
  test_concurrent_event_consistency()
  
  # TEST 5: Event delivery reliability
  test_event_delivery_reliability()
end

defp test_event_action_timing do
  {:ok, agent, pid} = create_test_agent(:demo, 
    initial_state: %{counter: 0})
  
  # Subscribe to action events
  EventBus.subscribe("action_executed")
  
  # Execute action that modifies state
  start_time = System.monotonic_time(:microsecond)
  {:ok, result} = Agent.Server.execute_action(pid, :increment, %{amount: 42})
  action_complete_time = System.monotonic_time(:microsecond)
  
  # Wait for event
  event = receive do
    {:event, %{type: "action_executed"} = event} -> event
  after
    2000 -> flunk("Action event not received")
  end
  
  event_received_time = System.monotonic_time(:microsecond)
  
  # CRITICAL: Event should arrive AFTER action completes (MIGHT FAIL)
  assert event_received_time > action_complete_time,
    "Event arrived before action completed - timing race condition"
  
  # Verify event data consistency with final state
  {:ok, final_agent} = Agent.Server.get_agent(pid)
  
  # Event should reflect the action result
  assert event.data.agent_id == agent.id
  assert event.data.action == :increment
  assert event.data.result == result
  
  # CRITICAL: Agent state should match event data (WILL LIKELY FAIL)
  assert final_agent.state.counter == 42,
    "Agent state (#{final_agent.state.counter}) doesn't match expected result (42)"
  
  # Event timestamp should be reasonable
  event_timestamp = DateTime.from_iso8601!(event.metadata.timestamp)
  action_timestamp = DateTime.utc_now()
  time_diff = DateTime.diff(action_timestamp, event_timestamp, :millisecond)
  
  assert abs(time_diff) < 1000,
    "Event timestamp #{time_diff}ms from action completion - too much drift"
end

defp test_event_ordering do
  {:ok, agent, pid} = create_test_agent(:demo, 
    initial_state: %{sequence: []})
  
  # Subscribe to events  
  EventBus.subscribe("action_executed")
  
  # Execute sequence of actions rapidly
  action_sequence = [
    {:add_to_sequence, %{value: "first"}},
    {:add_to_sequence, %{value: "second"}}, 
    {:add_to_sequence, %{value: "third"}},
    {:add_to_sequence, %{value: "fourth"}},
    {:add_to_sequence, %{value: "fifth"}}
  ]
  
  # Execute all actions as fast as possible
  for {action, params} <- action_sequence do
    Agent.Server.execute_action(pid, action, params)
  end
  
  # Collect all events
  events = collect_events("action_executed", 5, 3000)
  
  # CRITICAL: Events should arrive in same order as actions (WILL LIKELY FAIL)
  event_values = Enum.map(events, fn event ->
    event.data.params.value
  end)
  
  expected_order = ["first", "second", "third", "fourth", "fifth"]
  assert event_values == expected_order,
    "Event order #{inspect(event_values)} != action order #{inspect(expected_order)}"
  
  # Verify final agent state matches event sequence
  {:ok, final_agent} = Agent.Server.get_agent(pid)
  assert final_agent.state.sequence == expected_order,
    "Agent sequence #{inspect(final_agent.state.sequence)} != expected #{inspect(expected_order)}"
end

defp test_event_data_consistency do
  {:ok, agent, pid} = create_test_agent(:demo,
    initial_state: %{data: "initial"})
  
  EventBus.subscribe("action_executed")
  
  # Execute action that changes state
  {:ok, _result} = Agent.Server.execute_action(pid, :update_data, %{
    new_data: "updated_value"
  })
  
  # Get event
  event = receive do
    {:event, %{type: "action_executed"} = event} -> event
  after 1000 -> flunk("Event not received")
  end
  
  # Get current agent state
  {:ok, current_agent} = Agent.Server.get_agent(pid)
  
  # CRITICAL: Event should contain fresh agent data (WILL LIKELY FAIL)
  event_agent_state = Map.get(event.data, :agent_state, %{})
  
  assert event_agent_state == current_agent.state,
    "Event contains stale state: #{inspect(event_agent_state)} != #{inspect(current_agent.state)}"
  
  # Event should have fresh timestamp
  event_time = DateTime.from_iso8601!(event.metadata.timestamp)
  now = DateTime.utc_now()
  age_ms = DateTime.diff(now, event_time, :millisecond)
  
  assert age_ms < 500,
    "Event timestamp is #{age_ms}ms old - too stale"
end

defp test_concurrent_event_consistency do
  {:ok, agent, pid} = create_test_agent(:demo,
    initial_state: %{counter: 0, operations: []})
  
  EventBus.subscribe("action_executed")
  
  # Launch concurrent actions
  tasks = for i <- 1..20 do
    Task.async(fn ->
      Agent.Server.execute_action(pid, :concurrent_increment, %{
        id: i,
        amount: 1
      })
    end)
  end
  
  # Wait for all actions to complete
  results = Enum.map(tasks, &Task.await(&1, 5000))
  
  # Collect all events
  events = collect_events("action_executed", 20, 5000)
  
  # CRITICAL: Should receive exactly one event per action (MIGHT FAIL)
  assert length(events) == 20,
    "Expected 20 events, received #{length(events)} - events lost or duplicated"
  
  # All events should have unique operation IDs
  event_ids = Enum.map(events, & &1.data.params.id)
  unique_ids = Enum.uniq(event_ids)
  
  assert length(unique_ids) == length(event_ids),
    "Duplicate events detected: #{inspect(event_ids)}"
  
  # Events should cover all operation IDs
  expected_ids = 1..20 |> Enum.to_list()
  assert Enum.sort(event_ids) == expected_ids,
    "Missing event IDs: expected #{inspect(expected_ids)}, got #{inspect(Enum.sort(event_ids))}"
  
  # Final agent state should be consistent with events
  {:ok, final_agent} = Agent.Server.get_agent(pid)
  assert final_agent.state.counter == 20,
    "Final counter #{final_agent.state.counter} != expected 20"
end

defp test_event_delivery_reliability do
  {:ok, agent, pid} = create_test_agent(:demo)
  
  # Create multiple subscribers to test delivery reliability
  subscribers = for i <- 1..10 do
    {:ok, subscriber} = GenServer.start_link(TestEventCollector, [])
    EventBus.subscribe("action_executed", subscriber)
    subscriber
  end
  
  # Execute actions that should generate events
  for i <- 1..50 do
    Agent.Server.execute_action(pid, :ping, %{iteration: i})
  end
  
  # Give events time to propagate
  :timer.sleep(2000)
  
  # Verify all subscribers received all events
  for subscriber <- subscribers do
    events = get_collected_events(subscriber)
    
    # CRITICAL: All subscribers should receive all events (MIGHT FAIL)
    assert length(events) == 50,
      "Subscriber #{inspect(subscriber)} received #{length(events)} events, expected 50"
    
    # Events should be unique (no duplicates)
    iterations = Enum.map(events, & &1.data.params.iteration)
    unique_iterations = Enum.uniq(iterations)
    
    assert length(unique_iterations) == length(iterations),
      "Duplicate events in subscriber #{inspect(subscriber)}: #{inspect(iterations)}"
  end
end

# Helper functions
defp collect_events(event_type, count, timeout) do
  collect_events_loop(event_type, count, timeout, [])
end

defp collect_events_loop(_event_type, 0, _timeout, events) do
  Enum.reverse(events)
end

defp collect_events_loop(event_type, remaining, timeout, events) do
  receive do
    {:event, %{type: ^event_type} = event} ->
      collect_events_loop(event_type, remaining - 1, timeout, [event | events])
  after
    timeout -> 
      flunk("Only collected #{length(events)} events, expected #{remaining} more")
  end
end

defp get_collected_events(collector_pid) do
  ref = make_ref()
  send(collector_pid, {:get_events, ref, self()})
  
  receive do
    {:events, ^ref, events} -> events
  after
    1000 -> []
  end
end
```

## Expected Test Results

### What Will Break (Predictions)
1. **Event Timing**: Events will arrive before actions complete
2. **Event Ordering**: Events will arrive out of sequence from actions  
3. **Stale Data**: Events will contain old agent state information
4. **Missing Events**: Some events will be lost during concurrent operations
5. **Event Duplicates**: Race conditions will cause duplicate events

### Specific Failure Scenarios
```bash
Event arrived before action completed - timing race condition

Event order ["second", "first", "fourth", "third", "fifth"] != action order ["first", "second", "third", "fourth", "fifth"]

Event contains stale state: %{counter: 0} != %{counter: 42}

Expected 20 events, received 18 - events lost or duplicated  

Subscriber received 47 events, expected 50
```

### Why This Matters for Production
In production event-driven systems:
- **Workflow Corruption**: Out-of-order events break business logic
- **Data Consistency**: Stale event data causes incorrect decisions
- **Monitoring Failures**: Missing events break alerting and metrics
- **Integration Issues**: External systems receive inconsistent event streams
- **Audit Problems**: Event logs don't reflect actual operation sequence

### Real-World Impact Examples
- Order processing events arrive out of sequence, causing inventory errors
- User activity events contain stale data, breaking recommendation engines
- Payment events lost during high traffic, causing accounting discrepancies  
- Monitoring events arrive before operations complete, showing false states

## Success Criteria

The test fix is successful when:
1. **Event Timing**: Events arrive only after actions fully complete
2. **Ordering Guarantee**: Events arrive in same sequence as actions
3. **Data Freshness**: Events contain current, not stale, agent state
4. **Delivery Reliability**: All events delivered exactly once to all subscribers
5. **Concurrent Safety**: High concurrency doesn't cause event loss or duplication

This test fix will force implementation of:
- Synchronous event emission for critical events
- Event ordering guarantees through sequence numbers
- Fresh data inclusion in events
- Reliable delivery mechanisms
- Concurrent event handling improvements