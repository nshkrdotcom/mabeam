# Phase 1 Implementation Prompt: Core MabeamTestHelper Module

## Context Summary

You are implementing the core test helper module for the MABEAM project to eliminate 61 OTP standards violations and create a production-grade test suite. This is Phase 1 of a 4-phase implementation plan.

## Project Background

**MABEAM** is a multi-agent BEAM orchestration system built with Elixir/OTP. The current test suite has critical flaws:
- Uses `Process.sleep/1` causing flaky tests
- Missing process monitoring causing race conditions  
- Hardcoded global names causing test conflicts
- No proper cleanup causing resource leaks

## Standards to Follow

Based on OTP testing standards analysis, you must:

1. **NEVER use Process.sleep/1** - Use proper synchronization instead
2. **Always monitor processes** - Use `Process.monitor/1` with receive blocks
3. **Use unique naming** - Generate collision-free process names
4. **Implement proper cleanup** - Use `ExUnit.Callbacks.on_exit/1` for resource management
5. **Add timeout handling** - All receive blocks must have timeouts
6. **Leverage GenServer ordering** - Use GenServer.call for synchronization

## Current Issues in Test Suite

From the analysis report, these are the critical issues to fix:

### Process.sleep Violations (7 instances)
```elixir
# WRONG - Current pattern
Process.sleep(50)
assert some_condition()

# CORRECT - Use synchronization
result = GenServer.call(pid, :get_state)
assert expected_condition(result)
```

### Missing Process Monitoring (4 instances)
```elixir
# WRONG - Current pattern  
Process.exit(pid, :kill)
# Hope it crashed

# CORRECT - Use process monitoring
ref = Process.monitor(pid)
Process.exit(pid, :kill)
receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
after
  1000 -> flunk("Process did not terminate")
end
```

### Hardcoded Global Names (4 instances)
```elixir
# WRONG - Current pattern
{:ok, agent, _pid} = DemoAgent.start_link(type: :type1)

# CORRECT - Use unique names
test_id = make_ref()
agent_name = :"agent_#{:erlang.phash2(test_id)}"
{:ok, agent, _pid} = DemoAgent.start_link(name: agent_name, type: :type1)
```

## MABEAM Architecture Context

### Core Components
- **Mabeam.DemoAgent** - Main agent implementation
- **Mabeam.Foundation.Registry** - Agent registry service
- **Mabeam.Foundation.Communication.EventBus** - Event system
- **Mabeam.Foundation.Supervisor** - Main supervisor

### Agent Structure
```elixir
defmodule Mabeam.DemoAgent do
  def start_link(opts \\ []) do
    # Returns {:ok, agent_struct, pid}
  end
  
  def execute_action(pid, action, params) do
    # Returns {:ok, result} or {:error, reason}
  end
end
```

### Registry API
```elixir
defmodule Mabeam.Foundation.Registry do
  def get_agent(agent_name) do
    # Returns {:ok, agent} or {:error, :not_found}
  end
  
  def register_agent(agent) do
    # Returns :ok or {:error, reason}
  end
end
```

### EventBus API
```elixir
defmodule Mabeam.Foundation.Communication.EventBus do
  def subscribe(pid, patterns) do
    # Returns :ok
  end
  
  def emit(event) do
    # Returns :ok
  end
end
```

## Proven Patterns from Superlearner

Based on analysis of production-grade test helpers, implement these patterns:

### 1. Unique ID Generation
```elixir
defp generate_test_id do
  test_name = case Process.get(:ex_unit_test) do
    %{name: name} -> name |> to_string() |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    _ -> "test"
  end
  
  unique_id = :erlang.unique_integer([:positive])
  "#{test_name}_#{unique_id}"
end
```

### 2. Process Monitoring Pattern
```elixir
def wait_for_process_termination(pid, timeout \\ 5000) do
  if Process.alive?(pid) do
    ref = Process.monitor(pid)
    
    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:ok, reason}
    after
      timeout -> {:error, :timeout}
    end
  else
    {:ok, :already_dead}
  end
end
```

### 3. Cleanup Registration Pattern
```elixir
defp register_agent_for_cleanup(pid, name) do
  existing_cleanups = Process.get(:agent_cleanups, [])
  Process.put(:agent_cleanups, [{pid, name} | existing_cleanups])
end
```

### 4. Synchronization Without Sleep
```elixir
defp wait_loop_pattern(condition_fn, timeout) do
  start_time = System.monotonic_time(:millisecond)
  
  wait_loop = fn loop ->
    case condition_fn.() do
      :ok -> :ok
      :error ->
        if System.monotonic_time(:millisecond) - start_time > timeout do
          {:error, :timeout}
        else
          Process.sleep(10)  # Minimal delay only
          loop.(loop)
        end
    end
  end
  
  wait_loop.(wait_loop)
end
```

## Implementation Task

Create the file `test/support/mabeam_test_helper.ex` with the following requirements:

### Module Structure
```elixir
defmodule MabeamTestHelper do
  @moduledoc """
  Comprehensive test helper for MABEAM following OTP testing standards.
  
  This module provides utilities for:
  - Process lifecycle management with proper synchronization
  - Agent creation and cleanup with unique naming
  - Event system testing with proper wait mechanisms
  - Resource management and cleanup automation
  """
  
  require Logger
  
  # Configuration constants - define these
  @default_timeout 5000
  @cleanup_timeout 1000
  @sync_delay 10
  
  # Implement all functions below
end
```

### Required Functions

#### 1. Agent Lifecycle Management
```elixir
@doc """
Creates a test agent with unique naming and automatic cleanup.
"""
def create_test_agent(agent_type, opts \\ [])

@doc """
Waits for agent to reach specific state with proper synchronization.
"""
def wait_for_agent_state(agent_name, expected_state, timeout \\ @default_timeout)

@doc """
Executes agent action with proper error handling and synchronization.
"""
def execute_agent_action(pid, action, params, timeout \\ @default_timeout)
```

#### 2. Event System Helpers
```elixir
@doc """
Subscribes to events with automatic cleanup.
"""
def subscribe_to_events(event_patterns, opts \\ [])

@doc """
Waits for specific event with timeout and proper filtering.
"""
def wait_for_event(event_type, timeout \\ @default_timeout)

@doc """
Waits for multiple events in sequence with proper ordering.
"""
def wait_for_events(event_types, timeout \\ @default_timeout)
```

#### 3. Process Monitoring Helpers
```elixir
@doc """
Monitors process termination with proper synchronization.
"""
def wait_for_process_termination(pid, timeout \\ @default_timeout)

@doc """
Kills process and waits for termination with monitoring.
"""
def kill_and_wait(pid, timeout \\ @default_timeout)
```

#### 4. Registry Helpers
```elixir
@doc """
Waits for agent registration with proper synchronization.
"""
def wait_for_agent_registration(agent_name, timeout \\ @default_timeout)

@doc """
Waits for agent deregistration with proper synchronization.
"""
def wait_for_agent_deregistration(agent_name, timeout \\ @default_timeout)
```

#### 5. Cleanup Helpers
```elixir
@doc """
Comprehensive cleanup of all test resources.
"""
def cleanup_all_test_resources()
```

### Implementation Requirements

1. **Use unique naming for all processes** - Generate collision-free names
2. **Implement proper process monitoring** - Use monitor/receive patterns
3. **Add comprehensive cleanup** - Register all resources for cleanup
4. **Use proper synchronization** - No Process.sleep except minimal delays
5. **Add timeout handling** - All receive blocks need timeouts
6. **Include error handling** - Proper try/catch/rescue patterns
7. **Add logging** - Use Logger for debugging information

### Testing Requirements

Create a basic test file `test/support/mabeam_test_helper_test.exs` that:
1. Tests unique ID generation
2. Tests process monitoring functions
3. Tests cleanup registration
4. Tests synchronization patterns
5. Verifies no Process.sleep usage

## Expected Deliverables

1. **Complete implementation** of `test/support/mabeam_test_helper.ex`
2. **Basic test coverage** in `test/support/mabeam_test_helper_test.exs`
3. **Documentation** with examples for each function
4. **Zero Process.sleep usage** except for minimal synchronization delays
5. **Comprehensive error handling** with proper timeouts

## Success Criteria

- All functions implemented with proper OTP patterns
- Comprehensive cleanup automation
- Unique naming system prevents test conflicts
- Process monitoring eliminates race conditions
- Proper timeout handling prevents hanging tests
- Zero violations of OTP testing standards

## Files to Create

1. `test/support/mabeam_test_helper.ex` - Main implementation
2. `test/support/mabeam_test_helper_test.exs` - Test coverage

## Context Files for Reference

- `/home/home/p/g/n/elixir_ml/docs/unified_vision/mabeam/MABEAM_TEST_HELPER_IMPLEMENTATION_PLAN.md` - Complete implementation plan
- `/home/home/p/g/n/elixir_ml/docs/unified_vision/mabeam/TEST_ISSUES_REPORT.md` - Issues to fix
- `/home/home/p/g/n/superlearner/test/support/supervisor_test_helper.ex` - Proven patterns
- `/home/home/p/g/n/superlearner/test/support/sandbox_test_helper.ex` - Advanced patterns

This implementation forms the foundation for all subsequent phases and must be rock-solid to support the entire test suite transformation.