# Phase 3 Implementation Prompt: Performance and Stress Testing

## Context Summary

You are implementing performance and stress testing utilities for the MABEAM project as Phase 3 of the test suite transformation. This phase builds on the core helpers (Phase 1) and specialized helpers (Phase 2) to create comprehensive performance benchmarking and system stress testing capabilities.

## Prerequisites

**MUST BE COMPLETED FIRST:**
- Phase 1: Core `MabeamTestHelper` module at `test/support/mabeam_test_helper.ex`
- Phase 2: Specialized helpers at `test/support/{agent,system,event}_test_helper.ex`
- All basic testing infrastructure operational

## Project Background

**MABEAM** is a multi-agent BEAM orchestration system that must handle:
- **High-throughput agent creation** - Creating hundreds of agents rapidly
- **Concurrent agent operations** - Multiple agents executing actions simultaneously
- **Event system scalability** - Thousands of events per second
- **Memory efficiency** - Minimal memory footprint under load
- **Resource management** - Proper cleanup under high load conditions

## Performance Testing Requirements

From the superlearner analysis, implement these performance testing patterns:

### Memory Usage Tracking
```elixir
def measure_memory_usage(pid) do
  case Process.info(pid, :memory) do
    {:memory, memory} -> memory
    _ -> 0
  end
end
```

### Performance Measurement
```elixir
def measure_operation_time(operation_fn) do
  start_time = System.monotonic_time(:microsecond)
  result = operation_fn.()
  end_time = System.monotonic_time(:microsecond)
  
  {result, end_time - start_time}
end
```

### Stress Testing Pattern
```elixir
def stress_test_with_monitoring(operation_fn, count, opts \\ []) do
  parallel = Keyword.get(opts, :parallel, false)
  timeout = Keyword.get(opts, :timeout, 30_000)
  
  start_time = System.monotonic_time(:millisecond)
  
  results = if parallel do
    1..count
    |> Task.async_stream(fn i -> operation_fn.(i) end, timeout: timeout)
    |> Enum.to_list()
  else
    1..count |> Enum.map(operation_fn)
  end
  
  end_time = System.monotonic_time(:millisecond)
  
  analyze_stress_results(results, start_time, end_time, count)
end
```

## MABEAM Performance Characteristics

### Expected Performance Baselines
- **Agent creation**: <1ms per agent (up to 100 agents)
- **Action execution**: <10ms per action (simple actions)
- **Event propagation**: <5ms per event (up to 1000 subscribers)
- **Memory usage**: <1MB per agent (basic agent)
- **Registry operations**: <1ms per lookup/registration

### System Limits to Test
- **Maximum agents**: Test up to 1000 concurrent agents
- **Event throughput**: Test up to 10,000 events/second
- **Memory pressure**: Test with limited memory scenarios
- **Process limits**: Test near BEAM process limits
- **Network simulation**: Test with simulated network delays

## Proven Patterns from Superlearner

### Performance Measurement
```elixir
def measure_sandbox_creation_time(opts \\ []) do
  start_time = System.monotonic_time(:microsecond)
  
  case create_test_sandbox(opts) do
    {:ok, sandbox_info} ->
      end_time = System.monotonic_time(:microsecond)
      duration = end_time - start_time
      
      {:ok, sandbox_info, duration}
      
    {:error, reason} ->
      {:error, reason}
  end
end
```

### Memory Usage Analysis
```elixir
def measure_sandbox_memory_usage(sandbox_id) do
  case get_sandbox_info(sandbox_id) do
    {:ok, sandbox_info} ->
      app_memory = get_process_memory(sandbox_info.app_pid)
      supervisor_memory = get_process_memory(sandbox_info.supervisor_pid)
      
      children = Supervisor.which_children(sandbox_info.supervisor_pid)
      children_memory = children
        |> Enum.map(fn {_id, pid, _type, _modules} -> get_process_memory(pid) end)
        |> Enum.sum()
      
      total_memory = app_memory + supervisor_memory + children_memory
      
      {:ok, %{
        total: total_memory,
        app: app_memory,
        supervisor: supervisor_memory,
        children: children_memory
      }}
      
    {:error, reason} ->
      {:error, reason}
  end
end
```

### Stress Testing Implementation
```elixir
def stress_test_sandboxes(count, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 30_000)
  parallel = Keyword.get(opts, :parallel, false)
  
  start_time = System.monotonic_time(:millisecond)
  
  create_and_destroy = fn i ->
    sandbox_id = "stress_test_#{i}_#{:erlang.unique_integer([:positive])}"
    
    case create_sandbox(sandbox_id) do
      {:ok, _sandbox_info} ->
        case destroy_sandbox(sandbox_id) do
          :ok -> {:ok, i}
          {:error, reason} -> {:error, {i, reason}}
        end
        
      {:error, reason} ->
        {:error, {i, reason}}
    end
  end
  
  results = if parallel do
    1..count
    |> Task.async_stream(create_and_destroy, timeout: timeout)
    |> Enum.to_list()
  else
    1..count |> Enum.map(create_and_destroy)
  end
  
  end_time = System.monotonic_time(:millisecond)
  duration = end_time - start_time
  
  analyze_results(results, duration, count)
end
```

## Library Code Performance Optimizations (PERFORMANCE-SUPPORTING)

With core functionality stable from Phases 1-2, these optimizations can be implemented alongside performance testing to validate their impact:

### 1. Magic Number Extraction (2 instances)
**Problem:** Hard-coded values reduce maintainability and performance testing clarity
**Files:** 
- `lib/mabeam/foundation/communication/event_bus.ex:95` - `max_history: 1000`
- `lib/mabeam/foundation/agent/lifecycle.ex:108` - Timeout values

**Performance-Supporting Constants:**
```elixir
# lib/mabeam/foundation/communication/event_bus.ex
@default_max_history 1000
@default_cleanup_interval 5000
@max_subscribers_per_pattern 100

defp create_subscription_state(opts) do
  %{
    max_history: Keyword.get(opts, :max_history, @default_max_history),
    cleanup_interval: @default_cleanup_interval,
    max_subscribers: @max_subscribers_per_pattern
  }
end

# lib/mabeam/foundation/agent/lifecycle.ex
@default_start_timeout 5000
@default_stop_timeout 3000
@max_restart_attempts 3

defp start_agent_with_timeout(supervisor, opts) do
  timeout = Keyword.get(opts, :timeout, @default_start_timeout)
  GenServer.call(supervisor, {:start_agent, opts}, timeout)
end
```

### 2. Pattern Matching Optimization (1 instance)
**Problem:** Complex pattern matching in event bus reduces performance
**File:** `lib/mabeam/foundation/communication/event_bus.ex:275-305`

**Performance Optimizations:**
```elixir
# Extract pattern matching logic for better performance
defp match_event_pattern?(pattern, event_type) do
  case pattern do
    "*" -> true
    "**" -> true
    ^event_type -> true
    _ -> match_wildcard_pattern(pattern, event_type)
  end
end

defp match_wildcard_pattern(pattern, event_type) do
  case String.split(pattern, "*", parts: 2) do
    [prefix] -> 
      String.starts_with?(event_type, prefix)
    [prefix, suffix] -> 
      String.starts_with?(event_type, prefix) and 
      String.ends_with?(event_type, suffix)
  end
end

# Add performance tracking
defp track_pattern_matching_performance(pattern, event_type, start_time) do
  duration = System.monotonic_time(:microsecond) - start_time
  
  if duration > @slow_pattern_threshold do
    Logger.warning("Slow pattern matching", 
      pattern: pattern, 
      event_type: event_type, 
      duration_microseconds: duration
    )
  end
  
  :telemetry.execute([:mabeam, :event_bus, :pattern_match], 
    %{duration: duration}, 
    %{pattern: pattern, event_type: event_type}
  )
end
```

### 3. Performance-Critical Type Specifications (5 instances)
**Problem:** Missing @spec annotations on performance-critical functions
**Files:** Performance-critical functions that need type specifications for optimization

**Performance-Supporting Specs:**
```elixir
# lib/mabeam/foundation/communication/event_bus.ex
@spec emit(map()) :: :ok
@spec subscribe(pid(), [String.t()]) :: :ok
@spec get_subscribers(String.t()) :: [pid()]
@spec match_pattern(String.t(), String.t()) :: boolean()

# lib/mabeam/foundation/agent/lifecycle.ex  
@spec start_agent(pid(), keyword()) :: {:ok, pid()} | {:error, term()}
@spec stop_agent(pid(), keyword()) :: :ok | {:error, term()}

# lib/mabeam/foundation/registry.ex
@spec lookup_agent(String.t()) :: {:ok, pid()} | {:error, :not_found}
@spec register_agent(String.t(), pid()) :: :ok | {:error, term()}
```

**PERFORMANCE VALIDATION:** These optimizations will be validated by the performance testing infrastructure developed in parallel, ensuring measurable improvement.

## Implementation Task

Create a comprehensive performance testing module building on existing helpers:

### Performance Test Helper

**File:** `test/support/performance_test_helper.ex`

```elixir
defmodule PerformanceTestHelper do
  @moduledoc """
  Helper for performance and stress testing MABEAM components.
  
  This module provides utilities for:
  - Performance measurement and benchmarking
  - Memory usage tracking and analysis
  - Stress testing with configurable loads
  - Resource limit testing
  - Performance regression detection
  """
  
  import MabeamTestHelper
  import AgentTestHelper
  import SystemTestHelper
  import EventTestHelper
  
  require Logger
  
  # Performance testing constants
  @performance_timeout 30_000
  @stress_test_timeout 60_000
  @memory_measurement_interval 100
  @gc_force_interval 1000
  
  # Required functions to implement:
  
  ## Agent Performance Testing
  
  @doc """
  Measures agent creation performance across different scenarios.
  """
  def measure_agent_creation_performance(agent_count, opts \\ [])
  
  @doc """
  Measures agent action execution performance.
  """
  def measure_agent_action_performance(agent_scenarios, opts \\ [])
  
  @doc """
  Tests agent memory usage under different loads.
  """
  def measure_agent_memory_usage(agent_configs, opts \\ [])
  
  @doc """
  Stress tests agent lifecycle (create/destroy cycles).
  """
  def stress_test_agent_lifecycle(cycle_count, opts \\ [])
  
  ## System Performance Testing
  
  @doc """
  Measures system startup and initialization performance.
  """
  def measure_system_startup_performance(system_configs, opts \\ [])
  
  @doc """
  Tests multi-agent coordination performance.
  """
  def measure_coordination_performance(coordination_scenarios, opts \\ [])
  
  @doc """
  Measures system performance under high load.
  """
  def measure_system_load_performance(load_scenarios, opts \\ [])
  
  @doc """
  Tests system memory efficiency with large agent counts.
  """
  def measure_system_memory_efficiency(agent_counts, opts \\ [])
  
  ## Event System Performance Testing
  
  @doc """
  Measures event system throughput and latency.
  """
  def measure_event_system_performance(event_scenarios, opts \\ [])
  
  @doc """
  Tests event propagation performance with high subscriber counts.
  """
  def measure_event_propagation_performance(subscriber_counts, opts \\ [])
  
  @doc """
  Stress tests event system with high event rates.
  """
  def stress_test_event_system(event_rate, duration, opts \\ [])
  
  ## Registry Performance Testing
  
  @doc """
  Measures registry operation performance (lookup, register, unregister).
  """
  def measure_registry_performance(operation_counts, opts \\ [])
  
  @doc """
  Tests registry scalability with large agent counts.
  """
  def measure_registry_scalability(agent_counts, opts \\ [])
  
  ## Resource Limit Testing
  
  @doc """
  Tests system behavior near process limits.
  """
  def test_process_limit_behavior(limit_percentage, opts \\ [])
  
  @doc """
  Tests system behavior under memory pressure.
  """
  def test_memory_pressure_behavior(memory_limit, opts \\ [])
  
  @doc """
  Tests system recovery from resource exhaustion.
  """
  def test_resource_exhaustion_recovery(exhaustion_scenarios, opts \\ [])
  
  ## Performance Analysis and Reporting
  
  @doc """
  Analyzes performance test results and generates reports.
  """
  def analyze_performance_results(results, baseline_metrics \\ nil)
  
  @doc """
  Detects performance regressions compared to baseline.
  """
  def detect_performance_regression(current_results, baseline_results, threshold \\ 0.1)
  
  @doc """
  Generates performance benchmark report.
  """
  def generate_performance_report(test_results, opts \\ [])
end
```

## Detailed Implementation Requirements

### Agent Performance Testing

1. **Agent Creation Performance**
   - Measure time to create N agents
   - Test sequential vs parallel creation
   - Memory usage during creation
   - Cleanup time measurement

2. **Action Execution Performance**
   - Different action types and complexities
   - Concurrent action execution
   - Action timeout behavior
   - Error handling performance

3. **Memory Usage Analysis**
   - Agent memory footprint over time
   - Memory leaks detection
   - Garbage collection impact
   - Memory efficiency with different agent types

4. **Lifecycle Stress Testing**
   - Rapid create/destroy cycles
   - Memory stability over cycles
   - Performance degradation detection
   - Resource cleanup verification

### System Performance Testing

1. **System Startup Performance**
   - Time to initialize all components
   - Memory usage during startup
   - Component dependency resolution
   - Startup failure recovery

2. **Multi-Agent Coordination**
   - Coordination latency measurement
   - Throughput under coordination load
   - Coordination failure impact
   - Scalability with agent count

3. **High Load Testing**
   - System stability under load
   - Performance degradation patterns
   - Resource usage under load
   - Load balancing effectiveness

4. **Memory Efficiency**
   - Memory usage scaling with agents
   - Memory cleanup effectiveness
   - Memory fragmentation detection
   - Memory pressure handling

### Event System Performance

1. **Throughput and Latency**
   - Events per second measurement
   - Event delivery latency
   - Subscriber impact on performance
   - Event ordering overhead

2. **Propagation Performance**
   - Performance with many subscribers
   - Pattern matching efficiency
   - Event filtering performance
   - Subscriber cleanup impact

3. **Stress Testing**
   - High event rate handling
   - System stability under load
   - Memory usage during stress
   - Recovery from overload

### Registry Performance

1. **Operation Performance**
   - Lookup, register, unregister timing
   - Performance with large registries
   - Concurrent operation handling
   - Registry cleanup efficiency

2. **Scalability Testing**
   - Performance scaling with agent count
   - Memory usage scaling
   - Concurrent access performance
   - Registry consistency under load

### Resource Limit Testing

1. **Process Limits**
   - Behavior near BEAM process limits
   - Process cleanup under limits
   - Error handling at limits
   - Recovery from limit exhaustion

2. **Memory Pressure**
   - Performance under memory pressure
   - Memory allocation failures
   - Garbage collection impact
   - Memory recovery mechanisms

3. **Recovery Testing**
   - System recovery from resource exhaustion
   - Component restart behavior
   - Data consistency after recovery
   - Performance after recovery

## Testing Requirements

Create comprehensive tests for the performance helper:

**File:** `test/support/performance_test_helper_test.exs`

```elixir
defmodule PerformanceTestHelperTest do
  use ExUnit.Case
  import PerformanceTestHelper
  
  describe "agent performance testing" do
    test "measures agent creation performance" do
      {:ok, results} = measure_agent_creation_performance(10)
      
      assert results.total_count == 10
      assert results.success_count > 0
      assert results.duration_microseconds > 0
      assert results.agents_per_second > 0
    end
    
    test "measures agent memory usage" do
      agent_configs = [
        %{type: :simple, count: 5},
        %{type: :complex, count: 3}
      ]
      
      {:ok, results} = measure_agent_memory_usage(agent_configs)
      
      assert Map.has_key?(results, :simple)
      assert Map.has_key?(results, :complex)
      assert results.simple.average_memory > 0
    end
  end
  
  describe "system performance testing" do
    test "measures system startup performance" do
      system_configs = [
        %{agents: 5, event_subscribers: 10}
      ]
      
      {:ok, results} = measure_system_startup_performance(system_configs)
      
      assert results.startup_time > 0
      assert results.component_initialization_time > 0
      assert results.ready_time > 0
    end
  end
  
  describe "event system performance" do
    test "measures event system throughput" do
      event_scenarios = [
        %{event_count: 100, subscriber_count: 10}
      ]
      
      {:ok, results} = measure_event_system_performance(event_scenarios)
      
      assert results.events_per_second > 0
      assert results.average_latency > 0
      assert results.success_rate > 0.9
    end
  end
end
```

## Performance Benchmarks

Define expected performance baselines:

**File:** `test/support/performance_benchmarks.ex`

```elixir
defmodule PerformanceBenchmarks do
  @moduledoc """
  Performance benchmarks and baselines for MABEAM components.
  """
  
  # Agent performance baselines
  @agent_creation_baseline %{
    agents_per_second: 1000,
    memory_per_agent: 1024 * 1024,  # 1MB
    creation_time_ms: 1.0
  }
  
  # System performance baselines
  @system_startup_baseline %{
    startup_time_ms: 100,
    component_initialization_ms: 50,
    ready_time_ms: 200
  }
  
  # Event system baselines
  @event_system_baseline %{
    events_per_second: 10000,
    average_latency_ms: 1.0,
    max_latency_ms: 10.0
  }
  
  # Registry performance baselines
  @registry_baseline %{
    lookup_time_ms: 0.1,
    register_time_ms: 0.5,
    unregister_time_ms: 0.5
  }
  
  def get_baseline(component) do
    case component do
      :agent -> @agent_creation_baseline
      :system -> @system_startup_baseline
      :event_system -> @event_system_baseline
      :registry -> @registry_baseline
    end
  end
end
```

## Usage Examples

### Agent Performance Testing
```elixir
defmodule AgentPerformanceTest do
  use ExUnit.Case
  import PerformanceTestHelper
  
  test "agent creation performance meets baseline" do
    {:ok, results} = measure_agent_creation_performance(100)
    
    baseline = PerformanceBenchmarks.get_baseline(:agent)
    
    assert results.agents_per_second >= baseline.agents_per_second * 0.8
    assert results.average_memory_per_agent <= baseline.memory_per_agent * 1.2
  end
  
  test "agent memory usage is stable over time" do
    agent_configs = [%{type: :demo, count: 50}]
    
    {:ok, results} = measure_agent_memory_usage(agent_configs, monitor_duration: 5000)
    
    # Check memory doesn't grow over time
    assert results.memory_growth_rate < 0.1  # Less than 10% growth
    assert results.memory_leaks == []
  end
end
```

### System Stress Testing
```elixir
defmodule SystemStressTest do
  use ExUnit.Case
  import PerformanceTestHelper
  
  test "system handles high agent creation load" do
    {:ok, results} = stress_test_agent_lifecycle(1000, parallel: true)
    
    assert results.success_rate > 0.95
    assert results.average_cycle_time < 10.0  # Less than 10ms per cycle
    assert results.memory_stable == true
  end
  
  test "event system handles high throughput" do
    {:ok, results} = stress_test_event_system(10000, 5000)  # 10k events/sec for 5 seconds
    
    assert results.events_processed > 45000  # At least 90% processed
    assert results.system_stable == true
    assert results.memory_usage_stable == true
  end
end
```

## Expected Deliverables

### Library Performance Optimizations (VALIDATED BY TESTS)
1. **Constants extraction** - Replace 2 magic numbers with named constants
2. **Pattern matching optimization** - Optimize event bus pattern matching performance
3. **Performance-critical specs** - Add @spec annotations to 5 performance-critical functions

### Performance Testing Infrastructure (PRIMARY FOCUS)
4. **Performance test helper module**
   - `test/support/performance_test_helper.ex`

5. **Performance benchmarks**
   - `test/support/performance_benchmarks.ex`

6. **Comprehensive test coverage**
   - `test/support/performance_test_helper_test.exs`

7. **Performance test examples**
   - `test/performance/agent_performance_test.exs`
   - `test/performance/system_performance_test.exs`
   - `test/performance/event_performance_test.exs`

8. **Documentation**
   - Performance testing guide
   - Benchmark interpretation guide
   - Regression detection documentation

## Success Criteria

### Library Performance Optimizations
- Magic numbers extracted into named constants with performance impact measured
- Pattern matching optimized with measurable performance improvement
- Performance-critical functions have @spec annotations for optimization

### Performance Testing Infrastructure
- All performance testing functions implemented
- Comprehensive performance benchmarks defined
- Performance regression detection working
- Memory usage tracking accurate
- Stress testing covers all major components
- Performance reports generated automatically
- All tests pass consistently
- Performance optimizations validated by test results

## Files to Create/Modify

### Library Performance Optimizations
1. `lib/mabeam/foundation/communication/event_bus.ex` - Extract constants, optimize patterns
2. `lib/mabeam/foundation/agent/lifecycle.ex` - Extract timeout constants, add specs
3. `lib/mabeam/foundation/registry.ex` - Add performance-critical specs

### Performance Testing Infrastructure
4. `test/support/performance_test_helper.ex` - Main performance testing utilities
5. `test/support/performance_benchmarks.ex` - Performance baselines and benchmarks
6. `test/support/performance_test_helper_test.exs` - Test coverage for performance helper
7. `test/performance/agent_performance_test.exs` - Agent performance tests
8. `test/performance/system_performance_test.exs` - System performance tests
9. `test/performance/event_performance_test.exs` - Event system performance tests

## Context Files for Reference

- `test/support/mabeam_test_helper.ex` - Core helper (Phase 1)
- `test/support/{agent,system,event}_test_helper.ex` - Specialized helpers (Phase 2)
- `/home/home/p/g/n/superlearner/test/support/sandbox_test_helper.ex` - Performance patterns
- `/home/home/p/g/n/elixir_ml/docs/unified_vision/mabeam/TEST_ISSUES_REPORT.md` - Issues to address

This phase completes the testing infrastructure with comprehensive performance monitoring and stress testing capabilities needed for production-ready MABEAM deployment.