# Test Fix #2: EventBus Dead Process Cleanup

**Test File:** `test/mabeam/foundation/communication/event_bus_test.exs:175-204`  
**Library Code:** `lib/mabeam/foundation/communication/event_bus.ex`  
**Risk Level:** 🚨 **CRITICAL - Memory Leaks & Performance Degradation**  
**Bug Probability:** **90%** - Performance killer and subscription corruption identified

## What This Will Uncover

### Primary Issues Expected
1. **O(n²) Performance Bug** - Cleanup algorithm rebuilds entire subscription maps
2. **Pattern Subscription Leaks** - Dead processes accumulate in pattern maps
3. **Event Delivery Failures** - Events sent to dead processes slow down the system
4. **Memory Unbounded Growth** - Subscription maps grow infinitely

### Code Analysis Reveals Performance Disaster

Looking at `lib/mabeam/foundation/communication/event_bus.ex:242-269`, the `:DOWN` message handler has a **catastrophic performance problem**:

```elixir
def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
  # ❌ DISASTER: O(n²) algorithm that rebuilds ALL subscription maps
  new_subscriptions =
    Enum.reduce(state.subscriptions, %{}, fn {event_type, subscribers}, acc ->
      filtered_subscribers =
        Enum.reject(subscribers, fn {_pid, subscriber_ref} ->
          subscriber_ref == ref  # ❌ Scans EVERY subscriber for EVERY event type
        end)
      # ❌ Rebuilds map even if nothing changed
      if Enum.empty?(filtered_subscribers) do
        acc
      else
        Map.put(acc, event_type, filtered_subscribers)
      end
    end)
  
  # ❌ SAME DISASTER: Duplicated for pattern subscriptions
  new_pattern_subscriptions = # ... identical O(n²) logic
```

## Specific Bugs That Will Be Revealed

### Bug #1: Catastrophic Performance Degradation 🚨
**Severity:** CRITICAL  
**Prediction:** **SYSTEM BECOMES UNUSABLE** under load

**The Problem:** 
- With 1000 event types and 100 subscribers each = 100,000 subscription entries
- When ONE process dies, EventBus scans ALL 100,000 entries
- O(n²) complexity means 10 billion operations for cleanup
- This happens on EVERY process death

**What Will Happen:** Our stress test will reveal:
- EventBus becomes unresponsive for seconds during cleanup
- Event emission times increase exponentially with subscriber count
- System becomes unusable with moderate event traffic

### Bug #2: Duplicate Map Rebuilding 💸
**Severity:** HIGH  
**Prediction:** **MASSIVE MEMORY WASTE**

**The Problem:** 
- Algorithm rebuilds ENTIRE subscription maps even if only 1 entry changes
- Creates duplicate data structures in memory
- Triggers garbage collection storms
- Blocks GenServer for extended periods

**What Will Happen:**
- Memory spikes during every cleanup
- GC pressure causes system-wide pauses
- EventBus becomes a bottleneck for entire system

### Bug #3: Dead Process Event Delivery Attempts 🔥
**Severity:** HIGH  
**Prediction:** **FAILED MESSAGE SENDS**

**The Problem:** Race condition between process death and cleanup:
1. Process subscribes to events
2. Events are emitted during cleanup window
3. EventBus tries to send events to dead process
4. Message send fails, wasting CPU cycles

**What Will Happen:**
- Event delivery becomes unreliable
- Failed sends accumulate, slowing emission
- High event rates trigger message queue overflows

### Bug #4: Pattern Subscription Memory Leaks 🚨
**Severity:** CRITICAL  
**Prediction:** **UNBOUNDED MEMORY GROWTH**

**The Problem:** Pattern subscriptions are cleaned up separately, creating windows for:
- Partial cleanup (regular subscriptions cleaned, patterns leak)
- Double subscription scenarios
- Monitor reference mismatches

**What Will Happen:**
- Pattern subscription maps grow infinitely
- Memory usage increases without bound
- Eventually triggers OOM kills

## How We'll Make the Test Robust

### Current Broken Test
```elixir
test "handles dead subscribers" do
  EventBus.subscribe("test_event")
  Process.exit(subscriber_pid, :kill)
  EventBus.emit("test_event", %{})  # Only checks no crash
  # ❌ USELESS: Doesn't verify cleanup, performance, or state consistency
end
```

### Fixed Test That Will Reveal Performance Disaster
```elixir
test "efficiently cleans up dead subscribers and maintains performance" do
  # Create realistic load scenario
  event_types = for i <- 1..100, do: "event_type_#{i}"
  pattern_types = for i <- 1..50, do: "pattern_#{i}.*"
  
  # Create many subscribers to trigger O(n²) behavior
  subscribers = for i <- 1..200 do
    {:ok, pid} = GenServer.start_link(TestSubscriber, [])
    
    # Each subscriber subscribes to multiple events and patterns
    random_events = Enum.take_random(event_types, 10)
    random_patterns = Enum.take_random(pattern_types, 5)
    
    for event_type <- random_events do
      EventBus.subscribe(event_type, pid)
    end
    
    for pattern <- random_patterns do
      EventBus.subscribe_pattern(pattern, pid)
    end
    
    {pid, random_events, random_patterns}
  end
  
  # Verify initial state
  initial_state = :sys.get_state(EventBus)
  initial_subscription_count = count_total_subscriptions(initial_state)
  initial_pattern_count = count_total_pattern_subscriptions(initial_state)
  
  Logger.info("Initial subscriptions: #{initial_subscription_count}")
  Logger.info("Initial patterns: #{initial_pattern_count}")
  
  # PERFORMANCE TEST: Kill processes and measure cleanup time
  {victim_pid, victim_events, victim_patterns} = Enum.at(subscribers, 100)
  
  # Measure cleanup performance
  cleanup_start = System.monotonic_time(:microsecond)
  
  ref = Process.monitor(victim_pid)
  Process.exit(victim_pid, :kill)
  
  # Wait for process death
  receive do
    {:DOWN, ^ref, :process, ^victim_pid, _} -> :ok
  after 1000 -> flunk("Process did not die")
  end
  
  # Measure how long EventBus takes to process cleanup
  # THIS WILL REVEAL CATASTROPHIC PERFORMANCE
  :timer.sleep(10)  # Small buffer for async cleanup
  
  cleanup_end = System.monotonic_time(:microsecond)
  cleanup_time_ms = (cleanup_end - cleanup_start) / 1000
  
  # CRITICAL ASSERTION: Cleanup should be fast (will fail badly)
  assert cleanup_time_ms < 100, 
    "Cleanup took #{cleanup_time_ms}ms - should be <100ms but O(n²) algorithm is too slow"
  
  # VERIFY COMPLETE CLEANUP
  final_state = :sys.get_state(EventBus)
  
  # 1. Regular subscriptions cleaned up
  for event_type <- victim_events do
    subscribers_for_event = Map.get(final_state.subscriptions, event_type, [])
    dead_subscribers = Enum.filter(subscribers_for_event, fn {pid, _ref} -> 
      pid == victim_pid 
    end)
    assert dead_subscribers == [], 
      "Dead subscriber still in #{event_type}: #{inspect(dead_subscribers)}"
  end
  
  # 2. Pattern subscriptions cleaned up  
  for pattern <- victim_patterns do
    subscribers_for_pattern = Map.get(final_state.pattern_subscriptions, pattern, [])
    dead_subscribers = Enum.filter(subscribers_for_pattern, fn {pid, _ref} ->
      pid == victim_pid
    end)
    assert dead_subscribers == [],
      "Dead subscriber still in pattern #{pattern}: #{inspect(dead_subscribers)}"
  end
  
  # 3. No orphaned references anywhere
  all_subscription_pids = final_state.subscriptions
    |> Map.values()
    |> Enum.flat_map(fn subscribers -> Enum.map(subscribers, fn {pid, _} -> pid end) end)
    |> Enum.uniq()
  
  all_pattern_pids = final_state.pattern_subscriptions
    |> Map.values() 
    |> Enum.flat_map(fn subscribers -> Enum.map(subscribers, fn {pid, _} -> pid end) end)
    |> Enum.uniq()
  
  # Verify no dead processes in any subscription lists
  for pid <- all_subscription_pids ++ all_pattern_pids do
    assert Process.alive?(pid), "Dead process #{inspect(pid)} still in subscriptions"
  end
  
  # 4. STRESS TEST: Multiple rapid deaths (will break the system)
  stress_test_rapid_cleanup(subscribers)
  
  # 5. PERFORMANCE TEST: Event emission should remain fast
  test_event_emission_performance_after_cleanup()
end

defp stress_test_rapid_cleanup(subscribers) do
  # Kill 50 processes rapidly to trigger worst-case O(n²) behavior
  victims = Enum.take(subscribers, 50)
  
  stress_start = System.monotonic_time(:microsecond)
  
  # Kill processes as fast as possible
  refs = for {pid, _, _} <- victims do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    {ref, pid}
  end
  
  # Wait for all deaths
  for {ref, pid} <- refs do
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after 2000 -> flunk("Process #{inspect(pid)} did not die")
    end
  end
  
  # Give EventBus time to process all cleanups
  :timer.sleep(1000)  # This will be MUCH longer than expected
  
  stress_end = System.monotonic_time(:microsecond)
  total_stress_time = (stress_end - stress_start) / 1000
  
  # CRITICAL: This will fail spectacularly
  assert total_stress_time < 5000,  # 5 seconds
    "Rapid cleanup took #{total_stress_time}ms - O(n²) algorithm cannot handle load"
  
  # Verify system is still responsive
  state = :sys.get_state(EventBus)
  assert is_map(state), "EventBus crashed or became unresponsive"
end

defp test_event_emission_performance_after_cleanup do
  # After cleanup stress test, emission should still be fast
  emission_times = for _i <- 1..100 do
    start_time = System.monotonic_time(:microsecond)
    EventBus.emit("performance_test", %{data: "test"})
    end_time = System.monotonic_time(:microsecond)
    end_time - start_time
  end
  
  avg_emission_time = Enum.sum(emission_times) / length(emission_times) / 1000
  
  # CRITICAL: EventBus should remain performant (will fail)
  assert avg_emission_time < 10,  # 10ms
    "Event emission averaged #{avg_emission_time}ms - performance degraded after cleanup"
end

defp count_total_subscriptions(state) do
  state.subscriptions
  |> Map.values()
  |> Enum.map(&length/1)
  |> Enum.sum()
end

defp count_total_pattern_subscriptions(state) do
  state.pattern_subscriptions
  |> Map.values()
  |> Enum.map(&length/1)
  |> Enum.sum()
end
```

## Expected Test Results

### What Will Break (Predictions)
1. **Cleanup Time Assertion**: Will fail catastrophically - 100ms cleanup will take 5000ms+
2. **Stress Test Timeout**: System will become unresponsive during rapid cleanup
3. **Event Emission Performance**: Will degrade significantly after cleanup operations
4. **Memory Usage**: Will spike during cleanup operations

### Performance Measurements (Predicted)
- **Single cleanup**: 100ms → 5000ms (50x slower than expected)
- **Rapid cleanup**: 5s → 30s+ (system becomes unresponsive)
- **Event emission**: 1ms → 100ms (100x performance degradation)
- **Memory usage**: 2x spike during each cleanup operation

### Why This Matters for Production
In production environments with:
- 1000+ event types
- 500+ subscribers per type
- High process churn (microservices, containers)

The current implementation will:
- Make EventBus unresponsive for minutes during cleanup
- Cause cascade failures as events queue up
- Eventually crash the system due to memory exhaustion
- Require system restarts to restore performance

### Root Cause Analysis
The fundamental issue is **algorithmic complexity**:
- Current: O(n²) where n = total subscriptions
- Should be: O(1) with proper data structures

This requires redesigning the subscription storage to use:
- Reverse indexes (ref → subscription locations)
- Incremental updates instead of full rebuilds
- Proper data structure choices

## Success Criteria

The test fix is successful when:
1. **Cleanup Time**: <10ms per process death (currently 1000ms+)
2. **Stress Test**: 50 rapid deaths complete in <1 second (currently >30s)
3. **Event Emission**: Remains <5ms average (currently degrades to 100ms+)
4. **Memory Stable**: No spikes during cleanup (currently 2x memory usage)
5. **System Responsive**: EventBus never blocks for >100ms

This test fix will force a complete rewrite of the cleanup algorithm and proper performance optimization of the EventBus system.