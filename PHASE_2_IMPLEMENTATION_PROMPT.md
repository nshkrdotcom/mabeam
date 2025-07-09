# Phase 2 Implementation Prompt: Specialized Test Helpers

## Context Summary

You are implementing specialized test helpers for the MABEAM project as Phase 2 of the test suite transformation. This phase builds on the core `MabeamTestHelper` module from Phase 1 and creates domain-specific helpers for agent testing, system integration, and event coordination.

## Prerequisites

**MUST BE COMPLETED FIRST:**
- Phase 1: Core `MabeamTestHelper` module implemented at `test/support/mabeam_test_helper.ex`
- All basic synchronization, cleanup, and process monitoring patterns established
- Unique naming system operational

## Project Background

**MABEAM** is a multi-agent BEAM orchestration system requiring specialized testing approaches for:
- **Agent lifecycle management** - Starting, stopping, restarting agents
- **Multi-agent coordination** - Testing interactions between multiple agents
- **Event system integration** - Testing event propagation and handling
- **System state consistency** - Ensuring system remains consistent during operations

## Issues This Phase Addresses

From the TEST_ISSUES_REPORT.md analysis, this phase fixes:

### Agent Testing Issues (12 instances)
- Missing agent restart synchronization
- Inadequate agent action execution testing
- No multi-agent coordination testing
- Missing agent state consistency verification

### System Integration Issues (8 instances)
- Missing system-level testing patterns
- No integration between agents and registry
- Missing event system integration testing
- No system state verification

### Event System Issues (5 instances)
- Missing event subscription testing
- No event propagation verification
- Missing event filtering and ordering tests
- No event system synchronization

## MABEAM Architecture Deep Dive

### Agent Architecture
```elixir
defmodule Mabeam.DemoAgent do
  # Agent lifecycle
  def start_link(opts) do
    # Returns {:ok, agent_struct, pid}
  end
  
  def stop(pid) do
    # Graceful shutdown
  end
  
  # Agent actions
  def execute_action(pid, action, params) do
    # Returns {:ok, result} or {:error, reason}
  end
  
  # Agent state
  def get_state(pid) do
    # Returns current agent state
  end
end
```

### Registry Integration
```elixir
defmodule Mabeam.Foundation.Registry do
  def register_agent(agent) do
    # Registers agent in system
  end
  
  def get_agent(agent_name) do
    # Returns {:ok, agent} or {:error, :not_found}
  end
  
  def list_agents() do
    # Returns list of all agents
  end
  
  def unregister_agent(agent_name) do
    # Removes agent from registry
  end
end
```

### Event System Architecture
```elixir
defmodule Mabeam.Foundation.Communication.EventBus do
  def subscribe(pid, patterns) do
    # Subscribe to event patterns
  end
  
  def emit(event) do
    # Emit event to all subscribers
  end
  
  def unsubscribe(pid, patterns) do
    # Unsubscribe from patterns
  end
  
  def get_subscribers(pattern) do
    # Get current subscribers for pattern
  end
end
```

### System Supervision
```elixir
defmodule Mabeam.Foundation.Supervisor do
  # Supervises all MABEAM components
  # - Registry
  # - EventBus  
  # - Agent lifecycle managers
end
```

## Proven Patterns from Superlearner

### Agent Isolation Pattern
```elixir
def setup_isolated_agent(test_name) do
  unique_id = :erlang.unique_integer([:positive])
  agent_name = :"test_agent_#{test_name}_#{unique_id}"
  
  {:ok, agent, pid} = DemoAgent.start_link(name: agent_name)
  
  # Register for cleanup
  ExUnit.Callbacks.on_exit(fn ->
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after 100 -> :ok
      end
    end
  end)
  
  %{agent: agent, pid: pid, name: agent_name}
end
```

### Restart Testing Pattern
```elixir
def wait_for_agent_restart(agent_name, original_pid, timeout \\ 1000) do
  # Monitor original process death
  if Process.alive?(original_pid) do
    ref = Process.monitor(original_pid)
    receive do
      {:DOWN, ^ref, :process, ^original_pid, _} -> :ok
    after timeout -> {:error, :timeout}
    end
  end
  
  # Wait for new process to register
  wait_for_agent_registration(agent_name, timeout)
end
```

### Multi-Agent Coordination Pattern
```elixir
def create_agent_team(agent_configs) do
  agents = for {type, config} <- agent_configs do
    case create_test_agent(type, config) do
      {:ok, agent_info} -> agent_info
      {:error, reason} -> throw({:agent_creation_failed, reason})
    end
  end
  
  # Wait for all agents to be ready
  for agent <- agents do
    wait_for_agent_registration(agent.name)
  end
  
  agents
end
```

## Implementation Task

Create three specialized helper modules building on the core `MabeamTestHelper`:

### 1. Agent-Specific Test Helper

**File:** `test/support/agent_test_helper.ex`

```elixir
defmodule AgentTestHelper do
  @moduledoc """
  Specialized test helper for agent lifecycle and behavior testing.
  
  This module provides utilities for:
  - Agent creation with different isolation levels
  - Agent restart and recovery testing
  - Agent action execution and error handling
  - Agent state management and verification
  """
  
  import MabeamTestHelper
  
  # Required functions to implement:
  
  @doc """
  Creates an isolated agent for destructive testing.
  """
  def setup_destructive_agent_test(agent_type, opts \\ [])
  
  @doc """
  Creates a shared agent for read-only testing.
  """
  def setup_readonly_agent_test(agent_type, opts \\ [])
  
  @doc """
  Tests agent restart behavior with proper synchronization.
  """
  def test_agent_restart(agent_info, supervisor_pid)
  
  @doc """
  Tests agent action execution with comprehensive error handling.
  """
  def test_agent_action_execution(agent_info, test_scenarios)
  
  @doc """
  Verifies agent state consistency after operations.
  """
  def verify_agent_state_consistency(agent_info, expected_state)
  
  @doc """
  Tests agent error recovery scenarios.
  """
  def test_agent_error_recovery(agent_info, error_scenarios)
end
```

### 2. System Integration Test Helper

**File:** `test/support/system_test_helper.ex`

```elixir
defmodule SystemTestHelper do
  @moduledoc """
  Test helper for system-level integration testing.
  
  This module provides utilities for:
  - Complete MABEAM system setup and teardown
  - Multi-agent coordination testing
  - System state consistency verification
  - Integration between components
  """
  
  import MabeamTestHelper
  
  # Required functions to implement:
  
  @doc """
  Sets up a complete MABEAM system for integration testing.
  """
  def setup_integration_system(opts \\ [])
  
  @doc """
  Tests multi-agent coordination with proper synchronization.
  """
  def test_multi_agent_coordination(system_info, coordination_scenario)
  
  @doc """
  Verifies system state consistency across all components.
  """
  def verify_system_consistency(system_info)
  
  @doc """
  Tests registry integration with agent lifecycle.
  """
  def test_registry_integration(system_info, registry_operations)
  
  @doc """
  Tests event system integration with agent actions.
  """
  def test_event_system_integration(system_info, event_scenarios)
  
  @doc """
  Creates a system stress test scenario.
  """
  def create_system_stress_test(agent_count, operation_count)
end
```

### 3. Event System Test Helper

**File:** `test/support/event_test_helper.ex`

```elixir
defmodule EventTestHelper do
  @moduledoc """
  Test helper for event system testing.
  
  This module provides utilities for:
  - Event subscription and unsubscription testing
  - Event propagation and ordering verification
  - Event filtering and pattern matching
  - Event system synchronization
  """
  
  import MabeamTestHelper
  
  # Required functions to implement:
  
  @doc """
  Sets up event testing environment with proper cleanup.
  """
  def setup_event_test_environment(opts \\ [])
  
  @doc """
  Tests event subscription with automatic cleanup.
  """
  def test_event_subscription(event_patterns, opts \\ [])
  
  @doc """
  Tests event propagation with timing verification.
  """
  def test_event_propagation(events, expected_propagation)
  
  @doc """
  Tests event filtering and pattern matching.
  """
  def test_event_filtering(filter_scenarios)
  
  @doc """
  Tests event ordering and sequencing.
  """
  def test_event_ordering(event_sequence, expected_order)
  
  @doc """
  Tests event system recovery from failures.
  """
  def test_event_system_recovery(failure_scenarios)
end
```

## Detailed Implementation Requirements

### Agent Test Helper Requirements

1. **Isolation Levels**
   - `setup_destructive_agent_test/2` - For tests that kill/restart agents
   - `setup_readonly_agent_test/2` - For tests that only read agent state
   - Proper cleanup for both scenarios

2. **Restart Testing**
   - Monitor original process termination
   - Wait for supervisor to restart agent
   - Verify new process is different
   - Ensure agent is functional after restart

3. **Action Execution Testing**
   - Support for multiple test scenarios
   - Proper error handling for invalid actions
   - Timeout handling for long-running actions
   - State verification after each action

4. **Error Recovery Testing**
   - Test agent behavior after errors
   - Verify agent remains functional
   - Test error propagation to supervisors
   - Verify system stability after errors

### System Test Helper Requirements

1. **System Setup**
   - Create multiple agents with unique names
   - Setup event system subscription
   - Wait for all components to be ready
   - Comprehensive cleanup on test completion

2. **Multi-Agent Coordination**
   - Execute coordinated actions across agents
   - Verify proper event propagation
   - Check system state consistency
   - Handle coordination failures gracefully

3. **Integration Testing**
   - Test registry-agent integration
   - Test event system-agent integration
   - Test supervisor-agent integration
   - Verify component interaction correctness

4. **Stress Testing**
   - Create high-load scenarios
   - Monitor system performance
   - Verify system stability under load
   - Proper cleanup after stress tests

### Event Test Helper Requirements

1. **Subscription Management**
   - Test event pattern subscription
   - Test unsubscription cleanup
   - Verify subscription state
   - Handle subscription failures

2. **Event Propagation**
   - Test event delivery to subscribers
   - Verify event ordering
   - Test event filtering
   - Handle event system failures

3. **Pattern Matching**
   - Test wildcard patterns
   - Test specific event matching
   - Test complex pattern combinations
   - Verify pattern precedence

4. **Synchronization**
   - Wait for event propagation
   - Synchronize with event system
   - Handle event delivery timeouts
   - Verify event system consistency

## Testing Requirements

For each helper module, create comprehensive tests:

1. **`test/support/agent_test_helper_test.exs`**
   - Test agent creation and cleanup
   - Test restart synchronization
   - Test action execution patterns
   - Test error recovery scenarios

2. **`test/support/system_test_helper_test.exs`**
   - Test system setup and teardown
   - Test multi-agent coordination
   - Test system consistency verification
   - Test integration scenarios

3. **`test/support/event_test_helper_test.exs`**
   - Test event subscription patterns
   - Test event propagation
   - Test event filtering
   - Test event synchronization

## Usage Examples

### Agent Testing Example
```elixir
defmodule MyAgentTest do
  use ExUnit.Case
  import AgentTestHelper
  
  describe "destructive agent tests" do
    setup do
      setup_destructive_agent_test(:demo, type: :test_agent)
    end
    
    test "agent restart behavior", %{agent: agent, pid: pid} do
      # Kill agent and test restart
      {:ok, new_agent} = test_agent_restart(agent, supervisor_pid)
      
      # Verify agent is functional
      assert new_agent.pid != pid
      assert Process.alive?(new_agent.pid)
    end
  end
end
```

### System Integration Example
```elixir
defmodule MySystemTest do
  use ExUnit.Case
  import SystemTestHelper
  
  describe "multi-agent coordination" do
    setup do
      setup_integration_system(agents: [
        {:demo, type: :coordinator},
        {:demo, type: :worker}
      ])
    end
    
    test "agent coordination", %{system: system} do
      coordination_scenario = [
        {0, :start_task, %{task_id: "test_task"}},
        {1, :execute_task, %{task_id: "test_task"}}
      ]
      
      {:ok, results} = test_multi_agent_coordination(system, coordination_scenario)
      
      # Verify coordination worked
      assert length(results) == 2
      verify_system_consistency(system)
    end
  end
end
```

### Event System Example
```elixir
defmodule MyEventTest do
  use ExUnit.Case
  import EventTestHelper
  
  describe "event propagation" do
    setup do
      setup_event_test_environment(subscribers: 3)
    end
    
    test "event ordering", %{environment: env} do
      event_sequence = [
        %{type: :start, data: %{id: 1}},
        %{type: :process, data: %{id: 1}},
        %{type: :complete, data: %{id: 1}}
      ]
      
      expected_order = [:start, :process, :complete]
      
      :ok = test_event_ordering(event_sequence, expected_order)
    end
  end
end
```

## Expected Deliverables

1. **Three specialized helper modules**
   - `test/support/agent_test_helper.ex`
   - `test/support/system_test_helper.ex`
   - `test/support/event_test_helper.ex`

2. **Comprehensive test coverage**
   - `test/support/agent_test_helper_test.exs`
   - `test/support/system_test_helper_test.exs`
   - `test/support/event_test_helper_test.exs`

3. **Documentation and examples**
   - Detailed function documentation
   - Usage examples for each helper
   - Integration patterns with core helper

4. **OTP compliance**
   - Zero Process.sleep usage
   - Proper process monitoring
   - Comprehensive cleanup
   - Timeout handling

## Success Criteria

- All specialized helpers implemented with proper OTP patterns
- Comprehensive test coverage for each helper module
- Integration with core MabeamTestHelper working correctly
- Agent isolation and restart testing working reliably
- Multi-agent coordination testing implemented
- Event system testing comprehensive and reliable
- Zero flaky tests in helper implementations

## Files to Create

1. `test/support/agent_test_helper.ex` - Agent testing utilities
2. `test/support/system_test_helper.ex` - System integration utilities  
3. `test/support/event_test_helper.ex` - Event system utilities
4. `test/support/agent_test_helper_test.exs` - Agent helper tests
5. `test/support/system_test_helper_test.exs` - System helper tests
6. `test/support/event_test_helper_test.exs` - Event helper tests

## Context Files for Reference

- `test/support/mabeam_test_helper.ex` - Core helper (Phase 1 deliverable)
- `/home/home/p/g/n/elixir_ml/docs/unified_vision/mabeam/TEST_ISSUES_REPORT.md` - Issues to fix
- `/home/home/p/g/n/superlearner/test/support/supervisor_test_helper.ex` - Proven patterns
- `/home/home/p/g/n/superlearner/test/support/sandbox_test_helper.ex` - Advanced patterns

This phase creates the domain-specific testing infrastructure needed for comprehensive MABEAM testing while maintaining strict OTP compliance.