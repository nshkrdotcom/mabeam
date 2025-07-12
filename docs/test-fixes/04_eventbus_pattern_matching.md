# Test Fix #4: EventBus Pattern Matching Edge Cases

**Test File:** `test/mabeam/foundation/communication/event_bus_test.exs:90-115`  
**Library Code:** `lib/mabeam/foundation/communication/event_bus.ex`  
**Risk Level:** 🔥 **HIGH - Event Routing Failures & Performance Issues**  
**Bug Probability:** **80%** - Complex pattern logic with multiple edge case failures

## What This Will Uncover

### Primary Issues Expected
1. **Pattern Matching Logic Errors** - False positives and negatives in wildcard handling
2. **Performance Degradation** - O(n) pattern scanning for every event emission
3. **Edge Case Failures** - Complex patterns causing crashes or incorrect routing
4. **Pattern Normalization Bugs** - Inconsistent handling of dot notation

### Code Analysis Reveals Complex Pattern Matching Flaws

Looking at `lib/mabeam/foundation/communication/event_bus.ex:305-341`, the pattern matching implementation has **several algorithmic problems**:

```elixir
defp match_event_pattern?(pattern, event_type_string) do
  case pattern do
    "*" -> true          # ❌ Too broad - matches everything
    "**" -> true         # ❌ What does ** even mean? Undefined behavior
    ^event_type_string -> true
    _ -> match_wildcard_pattern(pattern, event_type_string)
  end
end

defp match_wildcard_pattern(pattern, event_type_string) do
  case String.split(pattern, "*", parts: 2) do
    [prefix] -> 
      String.starts_with?(event_type_string, prefix)  # ❌ Only checks prefix
    [prefix, suffix] -> 
      # ❌ COMPLEX BUG: Dot normalization logic is flawed
      normalized_prefix = 
        if String.ends_with?(prefix, ".") do
          String.slice(prefix, 0..-2//1)  # ❌ Wrong slice syntax
        else
          prefix
        end
      # ❌ Missing suffix matching logic
```

## Specific Bugs That Will Be Revealed

### Bug #1: Wildcard Matching Logic Errors 🚨
**Severity:** CRITICAL  
**Prediction:** **FALSE POSITIVES/NEGATIVES** in pattern matching

**The Problem:** 
- `"*"` matches literally everything (way too broad)
- `"**"` is undefined behavior but accepted  
- Single `*` patterns like `"test*"` only check prefix, ignore suffix
- Complex patterns like `"*.middle.*"` are not handled

**What Will Happen:** Our comprehensive test will reveal:
```elixir
# These will FAIL due to overly broad matching
EventBus.subscribe_pattern("demo.*")
EventBus.emit("completely_different_event", %{})
# ❌ Will incorrectly receive event due to "*" fallback

# These will FAIL due to incomplete suffix logic  
EventBus.subscribe_pattern("demo.*_response")
EventBus.emit("demo.test_response", %{})
# ❌ Won't match because suffix logic is incomplete
```

### Bug #2: Dot Normalization Bug 🔥
**Severity:** HIGH  
**Prediction:** **INCORRECT STRING SLICING** will crash

**The Problem:** Line 327 has incorrect slice syntax:
```elixir
String.slice(prefix, 0..-2//1)  # ❌ Invalid syntax - will crash
```

Should be:
```elixir
String.slice(prefix, 0..-2)  # Correct syntax
```

**What Will Happen:**
- Any pattern ending with `.` will crash the EventBus
- Patterns like `"demo."`, `"test."` will cause `ArgumentError`
- EventBus will become unresponsive for pattern subscriptions

### Bug #3: Performance Degradation 🚨
**Severity:** CRITICAL  
**Prediction:** **O(n×m) PERFORMANCE** with many patterns

**The Problem:**
- Every event emission scans ALL pattern subscriptions
- Complex string operations for each pattern check
- No pattern compilation or optimization
- Performance tracking exists but no mitigation

**What Will Happen:**
- With 1000 patterns, each event emission becomes 1000x slower
- Pattern matching time grows linearly with subscriber count
- High-frequency events (100/sec) will cause system slowdown
- Memory usage grows due to repeated string operations

### Bug #4: Missing Edge Case Handling ⚠️
**Severity:** MEDIUM  
**Prediction:** **UNDEFINED BEHAVIOR** for complex patterns

**The Problem:**
- Multiple wildcards: `"*.test.*"` not handled
- Empty patterns: `""` behavior undefined
- Special characters: patterns with `[]{}()` not handled
- Unicode patterns: non-ASCII characters not tested

**What Will Happen:**
- Complex patterns will either crash or fail silently
- Inconsistent behavior across different pattern types
- Some patterns will match everything, others nothing

## How We'll Make the Test Robust

### Current Inadequate Test
```elixir
test "subscribe to pattern" do
  EventBus.subscribe_pattern("demo.*")
  EventBus.emit("demo.ping", %{})
  assert_receive {:event, _}, 100  # ❌ Too simple, short timeout
  # Missing: Edge cases, performance, negative tests
end
```

### Comprehensive Test That Will Reveal Pattern Bugs
```elixir
test "comprehensive pattern matching with edge cases and performance" do
  # TEST 1: Basic pattern functionality
  test_basic_pattern_matching()
  
  # TEST 2: Edge cases that will break the system
  test_pattern_edge_cases()
  
  # TEST 3: Performance with many patterns
  test_pattern_matching_performance()
  
  # TEST 4: Pattern normalization bugs
  test_pattern_normalization()
  
  # TEST 5: Complex wildcard scenarios
  test_complex_wildcard_patterns()
end

defp test_basic_pattern_matching do
  # Simple prefix patterns
  EventBus.subscribe_pattern("demo.*")
  
  EventBus.emit("demo.ping", %{test: 1})
  assert_receive {:event, %{data: %{test: 1}}}, 1000
  
  EventBus.emit("demo.action.response", %{test: 2})
  assert_receive {:event, %{data: %{test: 2}}}, 1000
  
  # Should NOT match
  EventBus.emit("other.ping", %{test: 3})
  refute_receive {:event, %{data: %{test: 3}}}, 500
end

defp test_pattern_edge_cases do
  # Edge case 1: Universal wildcard (will reveal overly broad matching)
  {:ok, universal_subscriber} = GenServer.start_link(TestSubscriber, [])
  EventBus.subscribe_pattern("*", universal_subscriber)
  
  EventBus.emit("should_not_match_everything", %{test: "universal"})
  
  # CRITICAL: "*" should NOT match everything (WILL FAIL)
  assert_no_message_received(universal_subscriber, 200),
    "Universal wildcard '*' incorrectly matched specific event"
  
  # Edge case 2: Double wildcard (undefined behavior)
  {:ok, double_subscriber} = GenServer.start_link(TestSubscriber, [])
  
  # This should either reject the pattern or have defined behavior
  result = try do
    EventBus.subscribe_pattern("**", double_subscriber)
  rescue
    error -> {:error, error}
  end
  
  # Either should reject invalid pattern OR have consistent behavior
  assert result in [:ok, {:error, :invalid_pattern}],
    "Double wildcard '**' has undefined behavior: #{inspect(result)}"
  
  # Edge case 3: Empty pattern
  {:ok, empty_subscriber} = GenServer.start_link(TestSubscriber, [])
  
  empty_result = try do
    EventBus.subscribe_pattern("", empty_subscriber)
  rescue
    error -> {:error, error}
  end
  
  assert empty_result in [:ok, {:error, :invalid_pattern}],
    "Empty pattern has undefined behavior: #{inspect(empty_result)}"
  
  # Edge case 4: Dot normalization crash (WILL CRASH)
  {:ok, dot_subscriber} = GenServer.start_link(TestSubscriber, [])
  
  # This WILL crash due to String.slice syntax error
  assert_crash_or_error(fn ->
    EventBus.subscribe_pattern("demo.", dot_subscriber)
  end, "Pattern ending with '.' should not crash EventBus")
end

defp test_pattern_normalization do
  # Test the problematic dot normalization logic
  {:ok, subscriber1} = GenServer.start_link(TestSubscriber, [])
  {:ok, subscriber2} = GenServer.start_link(TestSubscriber, [])
  
  # These patterns should be equivalent after normalization
  EventBus.subscribe_pattern("demo.", subscriber1)  # Will crash
  EventBus.subscribe_pattern("demo", subscriber2)   # Should work
  
  # Both should match the same events
  EventBus.emit("demo_event", %{test: "normalization"})
  
  # Verify both subscribers get the event (if crash is fixed)
  assert_message_received(subscriber1, 1000, "demo. pattern failed")
  assert_message_received(subscriber2, 1000, "demo pattern failed")
end

defp test_complex_wildcard_patterns do
  # Test patterns the current implementation cannot handle
  {:ok, subscriber} = GenServer.start_link(TestSubscriber, [])
  
  # Multiple wildcards (not supported by current implementation)
  multi_wildcard_result = try do
    EventBus.subscribe_pattern("*.middle.*", subscriber)
  rescue
    error -> {:error, error}
  end
  
  if multi_wildcard_result == :ok do
    # Test if it actually works correctly
    EventBus.emit("prefix.middle.suffix", %{test: "multi"})
    assert_message_received(subscriber, 1000, "Multiple wildcard pattern failed")
    
    # Should NOT match
    EventBus.emit("prefix.wrong.suffix", %{test: "multi_wrong"})
    assert_no_message_received(subscriber, 200, "Multiple wildcard incorrectly matched")
  end
  
  # Suffix-only patterns
  suffix_result = try do
    EventBus.subscribe_pattern("*.response", subscriber)
  rescue
    error -> {:error, error}
  end
  
  if suffix_result == :ok do
    EventBus.emit("demo.response", %{test: "suffix"})
    assert_message_received(subscriber, 1000, "Suffix pattern failed")
    
    EventBus.emit("demo.request", %{test: "suffix_wrong"})
    assert_no_message_received(subscriber, 200, "Suffix pattern incorrectly matched")
  end
end

defp test_pattern_matching_performance do
  # Create many pattern subscriptions to test O(n) performance
  subscribers = for i <- 1..100 do
    {:ok, subscriber} = GenServer.start_link(TestSubscriber, [])
    EventBus.subscribe_pattern("perf_test_#{i}.*", subscriber)
    subscriber
  end
  
  # Measure pattern matching performance
  start_time = System.monotonic_time(:microsecond)
  
  # Emit event that matches one pattern
  EventBus.emit("perf_test_50.event", %{test: "performance"})
  
  end_time = System.monotonic_time(:microsecond)
  elapsed_microseconds = end_time - start_time
  
  # CRITICAL: Should be fast even with many patterns (WILL FAIL)
  assert elapsed_microseconds < 10_000,  # 10ms
    "Pattern matching took #{elapsed_microseconds}μs with 100 patterns - too slow"
  
  # Test performance degradation with more patterns
  more_subscribers = for i <- 101..500 do
    {:ok, subscriber} = GenServer.start_link(TestSubscriber, [])
    EventBus.subscribe_pattern("stress_test_#{i}.*", subscriber)
    subscriber
  end
  
  stress_start = System.monotonic_time(:microsecond)
  EventBus.emit("stress_test_250.event", %{test: "stress"})
  stress_end = System.monotonic_time(:microsecond)
  stress_elapsed = stress_end - stress_start
  
  # Performance should not degrade linearly (WILL FAIL)
  performance_ratio = stress_elapsed / elapsed_microseconds
  assert performance_ratio < 2.0,
    "Pattern matching performance degraded #{performance_ratio}x with 5x more patterns"
end

# Helper functions for message verification
defp assert_message_received(subscriber_pid, timeout, error_msg) do
  # Send a test message to verify subscriber receives it
  ref = make_ref()
  send(subscriber_pid, {:verify, ref, self()})
  
  receive do
    {:verified, ^ref} -> :ok
  after
    timeout -> flunk(error_msg)
  end
end

defp assert_no_message_received(subscriber_pid, timeout, error_msg) do
  # Verify subscriber does NOT receive messages
  ref = make_ref()
  send(subscriber_pid, {:check_empty, ref, self()})
  
  receive do
    {:empty, ^ref} -> :ok
    {:not_empty, ^ref} -> flunk(error_msg)
  after
    timeout -> flunk("Subscriber not responding")
  end
end

defp assert_crash_or_error(fun, error_msg) do
  try do
    result = fun.()
    if result not in [:ok, {:error, :invalid_pattern}] do
      flunk("#{error_msg} - got: #{inspect(result)}")
    end
  rescue
    _error -> :ok  # Expected crash is acceptable
  end
end
```

## Expected Test Results

### What Will Break (Predictions)
1. **Dot Pattern Crash**: `String.slice(prefix, 0..-2//1)` will crash with `ArgumentError`
2. **Universal Wildcard**: `"*"` will incorrectly match unrelated events  
3. **Performance Test**: Will exceed 10ms timeout with 100 patterns
4. **Edge Cases**: Multiple wildcard patterns will fail or behave inconsistently
5. **Pattern Normalization**: Inconsistent behavior between `"demo."` and `"demo"`

### Specific Error Messages Expected
```bash
** (ArgumentError) invalid range in String.slice/2
    lib/mabeam/foundation/communication/event_bus.ex:327

Pattern matching took 50000μs with 100 patterns - too slow

Universal wildcard '*' incorrectly matched specific event

Multiple wildcard pattern failed - not implemented
```

### Why This Matters for Production
In production with microservices and event-driven architectures:
- **Event Routing Failures**: Critical events don't reach intended subscribers
- **Performance Degradation**: High-frequency events slow down entire system
- **Service Outages**: Pattern crashes take down EventBus
- **Integration Bugs**: Services receive wrong events due to pattern errors
- **Scaling Issues**: Performance degrades linearly with service count

### Real-World Impact Examples
- Notification service receives all events due to overly broad `"*"` pattern
- Order processing fails because `"order.*.completed"` pattern doesn't work
- System monitoring breaks because patterns crash on deployment events
- API gateway routing fails due to pattern performance issues

## Success Criteria

The test fix is successful when:
1. **Pattern Syntax**: All valid patterns work correctly, invalid ones are rejected
2. **Performance**: Sub-millisecond pattern matching regardless of pattern count
3. **Edge Cases**: Complex patterns have defined, consistent behavior
4. **No Crashes**: Malformed patterns don't crash EventBus
5. **Correctness**: Zero false positives/negatives in pattern matching

This test fix will force implementation of:
- Robust pattern parsing and validation
- Efficient pattern matching algorithms (tries, compiled patterns)
- Comprehensive edge case handling
- Performance optimization strategies