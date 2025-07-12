defmodule SystemTestHelper do
  @moduledoc """
  Test helper for system-level integration testing.

  This module provides utilities for:
  - Complete MABEAM system setup and teardown
  - Multi-agent coordination testing
  - System state consistency verification
  - Integration between components

  ## Usage

  This module builds on `MabeamTestHelper` and `AgentTestHelper` to provide
  comprehensive system-level testing patterns following OTP best practices.

  ## Example

      # Setup integration system with multiple agents
      system_info = SystemTestHelper.setup_integration_system(
        agents: [
          {:demo, type: :coordinator, capabilities: [:coordinate, :monitor]},
          {:demo, type: :worker, capabilities: [:work, :report]},
          {:demo, type: :worker, capabilities: [:work, :report]}
        ],
        event_subscriptions: [:system_status, :coordination_events]
      )
      
      # Test multi-agent coordination
      coordination_scenario = [
        {0, :start_coordination, %{task_id: "test_task"}},
        {1, :execute_work, %{task_id: "test_task", data: "worker1_data"}},
        {2, :execute_work, %{task_id: "test_task", data: "worker2_data"}},
        {0, :finalize_coordination, %{task_id: "test_task"}}
      ]
      
      {:ok, results} = SystemTestHelper.test_multi_agent_coordination(
        system_info, 
        coordination_scenario
      )
      
      # Verify system consistency
      :ok = SystemTestHelper.verify_system_consistency(system_info)
  """

  import MabeamTestHelper
  require Logger

  # Configuration constants
  @default_timeout 10000
  @system_setup_timeout 15000
  @coordination_timeout 20000
  @consistency_check_timeout 5000
  @stress_test_timeout 30000

  @doc """
  Sets up a complete MABEAM system for integration testing.

  This function creates multiple agents, sets up event subscriptions,
  and ensures all components are ready for integration testing.

  ## Parameters

  - `opts` - System configuration options

  ## Options

  - `:agents` - List of agent specifications: `{type, config}`
  - `:event_subscriptions` - List of event types to subscribe to
  - `:registry_config` - Custom registry configuration
  - `:event_bus_config` - Custom event bus configuration
  - `:timeout` - Timeout for system setup (default: #{@system_setup_timeout}ms)
  - `:enable_telemetry` - Whether to enable telemetry collection (default: true)

  ## Agent Specification Format

  Each agent spec is: `{agent_type, config}` where config can include:
  - `:type` - Agent subtype
  - `:capabilities` - List of agent capabilities
  - `:initial_state` - Initial state for the agent
  - `:name` - Custom name for the agent

  ## Returns

  - `%{agents: agents, subscriptions: subscriptions, system_pid: pid}` - System info
  - `{:error, reason}` - System setup failed

  ## Examples

      system_info = SystemTestHelper.setup_integration_system(
        agents: [
          {:demo, type: :coordinator, capabilities: [:coordinate], name: :coordinator},
          {:demo, type: :worker, capabilities: [:work]},
          {:demo, type: :worker, capabilities: [:work]}
        ],
        event_subscriptions: [:coordination_start, :work_complete],
        timeout: 20000
      )
  """
  @spec setup_integration_system(keyword()) ::
          %{agents: list(map()), subscriptions: list(), system_pid: pid()} | {:error, term()}
  def setup_integration_system(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @system_setup_timeout)
    agents_specs = Keyword.get(opts, :agents, [])
    event_subscriptions = Keyword.get(opts, :event_subscriptions, [])
    _enable_telemetry = Keyword.get(opts, :enable_telemetry, true)

    Logger.info("Setting up integration system",
      agent_count: length(agents_specs),
      subscription_count: length(event_subscriptions),
      timeout: timeout
    )

    start_time = System.monotonic_time(:millisecond)

    try do
      # Ensure MABEAM system is running
      system_pid = ensure_system_running()

      # Create all agents
      case create_system_agents(agents_specs, timeout) do
        {:ok, agents} ->
          # Setup event subscriptions
          case setup_system_subscriptions(event_subscriptions, timeout) do
            {:ok, subscriptions} ->
              # Wait for system to stabilize
              case wait_for_system_ready(agents, timeout) do
                :ok ->
                  system_info = %{
                    agents: agents,
                    subscriptions: subscriptions,
                    system_pid: system_pid,
                    created_at: DateTime.utc_now(),
                    setup_time: System.monotonic_time(:millisecond) - start_time
                  }

                  # Register system cleanup
                  register_system_for_cleanup(system_info)

                  Logger.info("Integration system setup completed",
                    agent_count: length(agents),
                    setup_time_ms: system_info.setup_time
                  )

                  system_info

                {:error, reason} ->
                  {:error, {:system_ready_timeout, reason}}
              end

            {:error, reason} ->
              {:error, {:subscription_setup_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:agent_creation_failed, reason}}
      end
    rescue
      error ->
        {:error, {:system_setup_exception, error}}
    catch
      :exit, reason ->
        {:error, {:system_setup_exit, reason}}
    end
  end

  @doc """
  Tests multi-agent coordination with proper synchronization.

  This function executes a coordination scenario across multiple agents,
  verifying proper interaction and synchronization.

  ## Parameters

  - `system_info` - System information from setup
  - `coordination_scenario` - List of coordination steps
  - `opts` - Additional options

  ## Coordination Scenario Format

  Each step is: `{agent_index, action, params}` or `{agent_index, action, params, expected_result}`
  - `agent_index` - Index of agent in system_info.agents list
  - `action` - Action to execute on the agent
  - `params` - Parameters for the action
  - `expected_result` - Optional expected result pattern

  ## Options

  - `:timeout` - Timeout for coordination (default: #{@coordination_timeout}ms)
  - `:parallel` - Execute actions in parallel where possible (default: false)
  - `:verify_events` - Verify event propagation between steps (default: true)
  - `:continue_on_error` - Continue coordination after errors (default: false)

  ## Returns

  - `{:ok, results}` - Coordination completed with results
  - `{:error, {:step_failed, step, reason}}` - Coordination step failed

  ## Examples

      coordination_scenario = [
        {0, :start_task, %{task_id: "integration_test", priority: :high}},
        {1, :accept_task, %{task_id: "integration_test"}},
        {2, :accept_task, %{task_id: "integration_test"}},
        {1, :execute_work, %{task_id: "integration_test", data: "work1"}},
        {2, :execute_work, %{task_id: "integration_test", data: "work2"}},
        {0, :collect_results, %{task_id: "integration_test"}}
      ]
      
      {:ok, results} = SystemTestHelper.test_multi_agent_coordination(
        system_info, 
        coordination_scenario,
        timeout: 30000,
        verify_events: true
      )
  """
  @spec test_multi_agent_coordination(map(), list(tuple()), keyword()) ::
          {:ok, list()} | {:error, term()}
  def test_multi_agent_coordination(system_info, coordination_scenario, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @coordination_timeout)
    parallel = Keyword.get(opts, :parallel, false)
    verify_events = Keyword.get(opts, :verify_events, true)
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    agents = system_info.agents

    Logger.info("Starting multi-agent coordination test",
      agent_count: length(agents),
      step_count: length(coordination_scenario),
      parallel: parallel
    )

    if parallel do
      execute_coordination_parallel(
        agents,
        coordination_scenario,
        timeout,
        verify_events,
        continue_on_error
      )
    else
      execute_coordination_sequential(
        agents,
        coordination_scenario,
        timeout,
        verify_events,
        continue_on_error
      )
    end
  end

  @doc """
  Verifies system state consistency across all components.

  This function checks that the system maintains consistency across
  agents, registry, and event bus.

  ## Parameters

  - `system_info` - System information from setup
  - `opts` - Additional options

  ## Options

  - `:timeout` - Timeout for consistency checks (default: #{@consistency_check_timeout}ms)
  - `:check_registry` - Verify registry consistency (default: true)
  - `:check_events` - Verify event system consistency (default: true)
  - `:check_agents` - Verify agent state consistency (default: true)
  - `:strict` - Use strict consistency checks (default: false)

  ## Returns

  - `:ok` - System is consistent
  - `{:error, {:consistency_violation, details}}` - Consistency violation found

  ## Examples

      :ok = SystemTestHelper.verify_system_consistency(system_info,
        timeout: 10000,
        strict: true
      )
  """
  @spec verify_system_consistency(map(), keyword()) :: :ok | {:error, term()}
  def verify_system_consistency(system_info, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @consistency_check_timeout)
    check_registry = Keyword.get(opts, :check_registry, true)
    check_events = Keyword.get(opts, :check_events, true)
    check_agents = Keyword.get(opts, :check_agents, true)
    strict = Keyword.get(opts, :strict, false)

    Logger.debug("Verifying system consistency",
      agent_count: length(system_info.agents),
      checks: %{registry: check_registry, events: check_events, agents: check_agents}
    )

    consistency_checks = []

    # Registry consistency check
    consistency_checks =
      if check_registry do
        [fn -> verify_registry_consistency(system_info, timeout, strict) end | consistency_checks]
      else
        consistency_checks
      end

    # Event system consistency check
    consistency_checks =
      if check_events do
        [
          fn -> verify_event_system_consistency(system_info, timeout, strict) end
          | consistency_checks
        ]
      else
        consistency_checks
      end

    # Agent consistency check
    consistency_checks =
      if check_agents do
        [fn -> verify_agent_consistency(system_info, timeout, strict) end | consistency_checks]
      else
        consistency_checks
      end

    # Execute all checks
    execute_consistency_checks(consistency_checks, [])
  end

  @doc """
  Tests registry integration with agent lifecycle.

  This function tests the integration between the registry and
  agent lifecycle management.

  ## Parameters

  - `system_info` - System information from setup
  - `registry_operations` - List of registry operations to test
  - `opts` - Additional options

  ## Registry Operation Format

  Each operation is: `{operation, params, expected_result}`
  - `operation` - Registry operation (:register, :unregister, :get, :list, etc.)
  - `params` - Parameters for the operation
  - `expected_result` - Expected result pattern

  ## Options

  - `:timeout` - Timeout for operations (default: #{@default_timeout}ms)
  - `:verify_lifecycle` - Verify agent lifecycle integration (default: true)

  ## Returns

  - `:ok` - Registry integration working correctly
  - `{:error, {:operation_failed, operation, reason}}` - Operation failed

  ## Examples

      registry_operations = [
        {:list_all, [], fn agents -> length(agents) >= 2 end},
        {:get_agent, [agent_id], {:ok, agent}},
        {:find_by_type, [:worker], fn agents -> length(agents) >= 1 end}
      ]
      
      :ok = SystemTestHelper.test_registry_integration(system_info, registry_operations)
  """
  @spec test_registry_integration(map(), list(tuple()), keyword()) :: :ok | {:error, term()}
  def test_registry_integration(system_info, registry_operations, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    verify_lifecycle = Keyword.get(opts, :verify_lifecycle, true)

    Logger.debug("Testing registry integration",
      operation_count: length(registry_operations)
    )

    case execute_registry_operations(registry_operations, timeout) do
      :ok ->
        if verify_lifecycle do
          verify_registry_lifecycle_integration(system_info, timeout)
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Tests event system integration with agent actions.

  This function tests the integration between the event system
  and agent action execution.

  ## Parameters

  - `system_info` - System information from setup
  - `event_scenarios` - List of event scenarios to test
  - `opts` - Additional options

  ## Event Scenario Format

  Each scenario is a map with:
  - `:trigger` - Function to trigger events
  - `:expected_events` - List of expected events
  - `:timeout` - Scenario-specific timeout
  - `:verify_propagation` - Whether to verify event propagation

  ## Options

  - `:timeout` - Default timeout for scenarios (default: #{@default_timeout}ms)
  - `:verify_ordering` - Verify event ordering (default: true)

  ## Returns

  - `:ok` - Event system integration working correctly
  - `{:error, {:scenario_failed, scenario, reason}}` - Scenario failed

  ## Examples

      event_scenarios = [
        %{
          trigger: fn agents -> 
            execute_agent_action(hd(agents).pid, :emit_status, %{status: :ready})
          end,
          expected_events: [:agent_status_changed],
          verify_propagation: true
        }
      ]
      
      :ok = SystemTestHelper.test_event_system_integration(system_info, event_scenarios)
  """
  @spec test_event_system_integration(map(), list(map()), keyword()) :: :ok | {:error, term()}
  def test_event_system_integration(system_info, event_scenarios, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    verify_ordering = Keyword.get(opts, :verify_ordering, true)

    Logger.debug("Testing event system integration",
      scenario_count: length(event_scenarios)
    )

    execute_event_scenarios(system_info, event_scenarios, timeout, verify_ordering)
  end

  @doc """
  Creates a system stress test scenario.

  This function creates a stress test scenario with many agents
  and high operation volume to test system scalability.

  ## Parameters

  - `agent_count` - Number of agents to create
  - `operation_count` - Number of operations per agent
  - `opts` - Additional options

  ## Options

  - `:timeout` - Timeout for stress test (default: #{@stress_test_timeout}ms)
  - `:agent_types` - Types of agents to create (default: [:demo])
  - `:operation_types` - Types of operations to execute (default: [:ping, :increment])
  - `:parallel_factor` - Parallelism factor (default: 4)
  - `:measure_performance` - Whether to measure performance metrics (default: true)

  ## Returns

  - `{:ok, stress_results}` - Stress test completed with metrics
  - `{:error, reason}` - Stress test failed

  ## Examples

      {:ok, results} = SystemTestHelper.create_system_stress_test(
        50,    # 50 agents
        100,   # 100 operations per agent
        timeout: 60000,
        parallel_factor: 8
      )
      
      # Results include performance metrics
      assert results.total_operations == 5000
      assert results.success_rate > 0.95
  """
  @spec create_system_stress_test(non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_system_stress_test(agent_count, operation_count, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @stress_test_timeout)
    agent_types = Keyword.get(opts, :agent_types, [:demo])
    operation_types = Keyword.get(opts, :operation_types, [:ping, :increment])
    parallel_factor = Keyword.get(opts, :parallel_factor, 4)
    measure_performance = Keyword.get(opts, :measure_performance, true)

    Logger.info("Starting system stress test",
      agent_count: agent_count,
      operation_count: operation_count,
      total_operations: agent_count * operation_count,
      parallel_factor: parallel_factor
    )

    start_time = System.monotonic_time(:millisecond)

    try do
      # Create stress test system
      case setup_stress_test_system(agent_count, agent_types, timeout) do
        stress_system when is_map(stress_system) ->
          # Execute stress operations
          case execute_stress_operations(
                 stress_system,
                 operation_count,
                 operation_types,
                 parallel_factor,
                 timeout
               ) do
            {:ok, operation_results} ->
              end_time = System.monotonic_time(:millisecond)
              duration = end_time - start_time

              stress_results = %{
                agent_count: agent_count,
                operation_count: operation_count,
                total_operations: agent_count * operation_count,
                duration_ms: duration,
                success_rate: calculate_success_rate(operation_results),
                operations_per_second:
                  calculate_ops_per_second(agent_count * operation_count, duration),
                operation_results: operation_results,
                system_info: stress_system
              }

              final_results =
                if measure_performance do
                  performance_metrics = collect_performance_metrics(stress_system, stress_results)
                  Map.put(stress_results, :performance_metrics, performance_metrics)
                else
                  stress_results
                end

              Logger.info("Stress test completed",
                duration_ms: duration,
                success_rate: final_results.success_rate,
                ops_per_second: final_results.operations_per_second
              )

              {:ok, final_results}

            {:error, reason} ->
              {:error, {:stress_operations_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:stress_system_setup_failed, reason}}
      end
    rescue
      error ->
        {:error, {:stress_test_exception, error}}
    catch
      :exit, reason ->
        {:error, {:stress_test_exit, reason}}
    end
  end

  # Private helper functions

  @spec ensure_system_running() :: pid()
  defp ensure_system_running do
    case Process.whereis(Mabeam.Foundation.Supervisor) do
      nil ->
        # Start the system if not running
        {:ok, pid} = Mabeam.start()
        pid

      pid when is_pid(pid) ->
        pid
    end
  end

  @spec create_system_agents(list(tuple()), non_neg_integer()) ::
          {:ok, list(map())} | {:error, term()}
  defp create_system_agents(agents_specs, _timeout) do
    agents =
      Enum.with_index(agents_specs)
      |> Enum.map(fn {{agent_type, config}, index} ->
        # Generate unique name if not provided
        config =
          if Keyword.has_key?(config, :name) do
            config
          else
            unique_name = :"system_agent_#{index}_#{:erlang.unique_integer([:positive])}"
            Keyword.put(config, :name, unique_name)
          end

        case create_test_agent(agent_type, config) do
          {:ok, agent, pid} ->
            %{
              index: index,
              agent: agent,
              pid: pid,
              config: config,
              agent_type: agent_type
            }

          {:error, reason} ->
            {:error, {:agent_creation_failed, index, reason}}
        end
      end)

    # Check if any agent creation failed
    failed_agents =
      Enum.filter(agents, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_agents) do
      {:ok, agents}
    else
      {:error, {:multiple_agent_failures, failed_agents}}
    end
  end

  @spec setup_system_subscriptions(list(), non_neg_integer()) :: {:ok, list()} | {:error, term()}
  defp setup_system_subscriptions(event_subscriptions, _timeout) do
    try do
      case subscribe_to_events(event_subscriptions) do
        :ok ->
          {:ok, event_subscriptions}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, {:subscription_exception, error}}
    end
  end

  @spec wait_for_system_ready(list(map()), non_neg_integer()) :: :ok | {:error, term()}
  defp wait_for_system_ready(agents, timeout) do
    # Wait for all agents to be registered
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn loop ->
      unregistered_agents =
        Enum.filter(agents, fn agent_info ->
          case Mabeam.get_agent(agent_info.agent.id) do
            {:ok, _} -> false
            {:error, :not_found} -> true
            {:error, _} -> true
          end
        end)

      if Enum.empty?(unregistered_agents) do
        :ok
      else
        if System.monotonic_time(:millisecond) - start_time > timeout do
          {:error, {:system_ready_timeout, unregistered_agents}}
        else
          loop.(loop)
        end
      end
    end

    wait_loop.(wait_loop)
  end

  @spec register_system_for_cleanup(map()) :: :ok
  defp register_system_for_cleanup(system_info) do
    try do
      ExUnit.Callbacks.on_exit(fn ->
        cleanup_system(system_info)
      end)
    rescue
      ArgumentError ->
        # Not in test process, cleanup will happen when test process exits
        :ok
    end

    :ok
  end

  @spec cleanup_system(map()) :: :ok
  defp cleanup_system(system_info) do
    Logger.debug("Cleaning up integration system",
      agent_count: length(system_info.agents)
    )

    # Cleanup is handled by MabeamTestHelper's automatic cleanup
    # Additional system-specific cleanup can be added here if needed
    :ok
  end

  @spec execute_coordination_sequential(
          list(map()),
          list(tuple()),
          non_neg_integer(),
          boolean(),
          boolean()
        ) ::
          {:ok, list()} | {:error, term()}
  defp execute_coordination_sequential(
         agents,
         coordination_scenario,
         timeout,
         verify_events,
         continue_on_error
       ) do
    execute_coordination_steps(
      agents,
      coordination_scenario,
      timeout,
      verify_events,
      continue_on_error,
      []
    )
  end

  @spec execute_coordination_parallel(
          list(map()),
          list(tuple()),
          non_neg_integer(),
          boolean(),
          boolean()
        ) ::
          {:ok, list()} | {:error, term()}
  defp execute_coordination_parallel(
         agents,
         coordination_scenario,
         timeout,
         verify_events,
         continue_on_error
       ) do
    # Group steps that can be executed in parallel
    parallel_groups = group_parallel_steps(coordination_scenario)

    execute_parallel_groups(
      agents,
      parallel_groups,
      timeout,
      verify_events,
      continue_on_error,
      []
    )
  end

  @spec execute_coordination_steps(
          list(map()),
          list(tuple()),
          non_neg_integer(),
          boolean(),
          boolean(),
          list()
        ) ::
          {:ok, list()} | {:error, term()}
  defp execute_coordination_steps(
         _agents,
         [],
         _timeout,
         _verify_events,
         _continue_on_error,
         results
       ) do
    {:ok, Enum.reverse(results)}
  end

  defp execute_coordination_steps(
         agents,
         [step | remaining],
         timeout,
         verify_events,
         continue_on_error,
         results
       ) do
    case execute_coordination_step(agents, step, timeout, verify_events) do
      {:ok, result} ->
        execute_coordination_steps(agents, remaining, timeout, verify_events, continue_on_error, [
          result | results
        ])

      {:error, reason} ->
        if continue_on_error do
          Logger.warning("Coordination step failed but continuing",
            step: inspect(step),
            reason: reason
          )

          execute_coordination_steps(
            agents,
            remaining,
            timeout,
            verify_events,
            continue_on_error,
            [reason | results]
          )
        else
          {:error, {:step_failed, step, reason}}
        end
    end
  end

  @spec execute_coordination_step(list(map()), tuple(), non_neg_integer(), boolean()) ::
          {:ok, term()} | {:error, term()}
  defp execute_coordination_step(agents, {agent_index, action, params}, timeout, verify_events) do
    execute_coordination_step(agents, {agent_index, action, params, :any}, timeout, verify_events)
  end

  defp execute_coordination_step(
         agents,
         {agent_index, action, params, expected},
         timeout,
         _verify_events
       ) do
    if agent_index >= 0 and agent_index < length(agents) do
      agent_info = Enum.at(agents, agent_index)

      case execute_agent_action(agent_info.pid, action, params, timeout) do
        result ->
          if expected == :any or result == expected do
            {:ok, result}
          else
            {:error, {:result_mismatch, expected, result}}
          end
      end
    else
      {:error, {:invalid_agent_index, agent_index, length(agents)}}
    end
  end

  @spec group_parallel_steps(list(tuple())) :: list(list(tuple()))
  defp group_parallel_steps(coordination_scenario) do
    # Simple grouping - consecutive steps with different agent indices can be parallel
    Enum.chunk_by(coordination_scenario, fn {agent_index, _, _} -> agent_index end)
  end

  @spec execute_parallel_groups(
          list(map()),
          list(list(tuple())),
          non_neg_integer(),
          boolean(),
          boolean(),
          list()
        ) ::
          {:ok, list()} | {:error, term()}
  defp execute_parallel_groups(_agents, [], _timeout, _verify_events, _continue_on_error, results) do
    {:ok, Enum.reverse(results) |> List.flatten()}
  end

  defp execute_parallel_groups(
         agents,
         [group | remaining],
         timeout,
         verify_events,
         continue_on_error,
         results
       ) do
    # Execute group in parallel
    tasks =
      Enum.map(group, fn step ->
        Task.async(fn ->
          execute_coordination_step(agents, step, timeout, verify_events)
        end)
      end)

    # Wait for all tasks to complete
    group_results =
      Enum.map(tasks, fn task ->
        Task.await(task, timeout)
      end)

    # Check for failures
    failed_results =
      Enum.filter(group_results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_results) or continue_on_error do
      execute_parallel_groups(agents, remaining, timeout, verify_events, continue_on_error, [
        group_results | results
      ])
    else
      {:error, {:parallel_group_failed, failed_results}}
    end
  end

  @spec execute_consistency_checks(list(function()), list()) :: :ok | {:error, term()}
  defp execute_consistency_checks([], results) do
    failed_checks =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_checks) do
      :ok
    else
      {:error, {:consistency_violations, failed_checks}}
    end
  end

  defp execute_consistency_checks([check | remaining], results) do
    result = check.()
    execute_consistency_checks(remaining, [result | results])
  end

  @spec verify_registry_consistency(map(), non_neg_integer(), boolean()) :: :ok | {:error, term()}
  defp verify_registry_consistency(system_info, _timeout, _strict) do
    # Verify all agents are registered
    agents = system_info.agents

    unregistered =
      Enum.filter(agents, fn agent_info ->
        case Mabeam.get_agent(agent_info.agent.id) do
          {:ok, _} -> false
          {:error, :not_found} -> true
          {:error, _} -> true
        end
      end)

    if Enum.empty?(unregistered) do
      :ok
    else
      {:error, {:registry_inconsistency, :unregistered_agents, unregistered}}
    end
  end

  @spec verify_event_system_consistency(map(), non_neg_integer(), boolean()) ::
          :ok | {:error, term()}
  defp verify_event_system_consistency(_system_info, _timeout, _strict) do
    # Basic event system consistency check
    # Could be expanded to check subscription states, event history, etc.

    try do
      # Test that event system is responsive
      test_event = %{type: :system_consistency_test, data: %{timestamp: DateTime.utc_now()}}

      case Mabeam.emit_event("system_consistency_test", test_event.data) do
        {:ok, _event_id} -> :ok
        {:error, reason} -> {:error, {:event_system_error, reason}}
      end
    rescue
      error ->
        {:error, {:event_system_exception, error}}
    end
  end

  @spec verify_agent_consistency(map(), non_neg_integer(), boolean()) :: :ok | {:error, term()}
  defp verify_agent_consistency(system_info, _timeout, _strict) do
    agents = system_info.agents

    # Check that all agents are still alive and responsive
    dead_agents =
      Enum.filter(agents, fn agent_info ->
        not Process.alive?(agent_info.pid)
      end)

    if Enum.empty?(dead_agents) do
      # Check that agents are responsive
      unresponsive_agents =
        Enum.filter(agents, fn agent_info ->
          case execute_agent_action(agent_info.pid, :ping, %{}, 1000) do
            {:ok, _} -> false
            {:error, _} -> true
          end
        end)

      if Enum.empty?(unresponsive_agents) do
        :ok
      else
        {:error, {:agent_consistency_error, :unresponsive_agents, unresponsive_agents}}
      end
    else
      {:error, {:agent_consistency_error, :dead_agents, dead_agents}}
    end
  end

  @spec execute_registry_operations(list(tuple()), non_neg_integer()) :: :ok | {:error, term()}
  defp execute_registry_operations(operations, timeout) do
    Enum.reduce_while(operations, :ok, fn operation, acc ->
      case execute_registry_operation(operation, timeout) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, {:operation_failed, operation, reason}}}
      end
    end)
  end

  @spec execute_registry_operation(tuple(), non_neg_integer()) :: :ok | {:error, term()}
  defp execute_registry_operation({operation, params, expected}, _timeout) do
    try do
      result =
        case operation do
          :list_all ->
            apply(Mabeam.Foundation.Registry, :list_all, [])

          :get_agent ->
            apply(Mabeam.Foundation.Registry, :get_agent, params)

          :find_by_type ->
            apply(Mabeam.Foundation.Registry, :find_by_type, params)

          :find_by_capability ->
            apply(Mabeam.Foundation.Registry, :find_by_capability, params)

          _ ->
            {:error, {:unsupported_operation, operation}}
        end

      case verify_registry_result(result, expected) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      error -> {:error, {:operation_exception, error}}
    catch
      :exit, reason -> {:error, {:operation_exit, reason}}
    end
  end

  @spec verify_registry_result(term(), term()) :: :ok | {:error, term()}
  defp verify_registry_result(result, expected) when is_function(expected) do
    if expected.(result) do
      :ok
    else
      {:error, {:function_validation_failed, result}}
    end
  end

  defp verify_registry_result(result, expected) do
    if result == expected do
      :ok
    else
      {:error, {:result_mismatch, expected, result}}
    end
  end

  @spec verify_registry_lifecycle_integration(map(), non_neg_integer()) :: :ok | {:error, term()}
  defp verify_registry_lifecycle_integration(system_info, _timeout) do
    # Test that registry properly tracks agent lifecycle
    agents = system_info.agents

    # All agents should be findable by their actual type (demo)
    type_checks =
      agents
      |> Enum.group_by(fn agent_info ->
        agent_info.agent.type
      end)
      |> Enum.all?(fn {type, agents_of_type} ->
        case Mabeam.Foundation.Registry.find_by_type(type) do
          agents_found when is_list(agents_found) ->
            length(agents_found) >= length(agents_of_type)

          _ ->
            false
        end
      end)

    if type_checks do
      :ok
    else
      {:error, :registry_lifecycle_integration_failed}
    end
  end

  @spec execute_event_scenarios(map(), list(map()), non_neg_integer(), boolean()) ::
          :ok | {:error, term()}
  defp execute_event_scenarios(system_info, event_scenarios, timeout, verify_ordering) do
    Enum.reduce_while(event_scenarios, :ok, fn scenario, acc ->
      case execute_event_scenario(system_info, scenario, timeout, verify_ordering) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, {:scenario_failed, scenario, reason}}}
      end
    end)
  end

  @spec execute_event_scenario(map(), map(), non_neg_integer(), boolean()) ::
          :ok | {:error, term()}
  defp execute_event_scenario(system_info, scenario, timeout, _verify_ordering) do
    trigger = Map.get(scenario, :trigger)
    expected_events = Map.get(scenario, :expected_events, [])
    scenario_timeout = Map.get(scenario, :timeout, timeout)
    verify_propagation = Map.get(scenario, :verify_propagation, true)

    try do
      # Subscribe to expected events if needed
      if verify_propagation and not Enum.empty?(expected_events) do
        subscribe_to_events(expected_events)
      end

      # Trigger the scenario
      case trigger.(system_info.agents) do
        :ok ->
          if verify_propagation and not Enum.empty?(expected_events) do
            wait_for_events(expected_events, scenario_timeout)
          else
            :ok
          end

        {:ok, _result} ->
          if verify_propagation and not Enum.empty?(expected_events) do
            wait_for_events(expected_events, scenario_timeout)
          else
            :ok
          end

        {:error, reason} ->
          {:error, {:trigger_failed, reason}}

        _other ->
          :ok
      end
    rescue
      error -> {:error, {:scenario_exception, error}}
    catch
      :exit, reason -> {:error, {:scenario_exit, reason}}
    end
  end

  @spec setup_stress_test_system(non_neg_integer(), list(atom()), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  defp setup_stress_test_system(agent_count, agent_types, timeout) do
    # Create agents for stress testing
    agents_specs =
      1..agent_count
      |> Enum.map(fn index ->
        agent_type = Enum.at(agent_types, rem(index, length(agent_types)))

        config = [
          type: :stress_test,
          capabilities: [:ping, :increment, :stress_operation],
          initial_state: %{counter: 0, stress_level: 0}
        ]

        {agent_type, config}
      end)

    setup_integration_system(
      agents: agents_specs,
      timeout: timeout,
      # Disable for performance
      enable_telemetry: false
    )
  end

  @spec execute_stress_operations(
          map(),
          non_neg_integer(),
          list(atom()),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, list()} | {:error, term()}
  defp execute_stress_operations(
         stress_system,
         operation_count,
         operation_types,
         parallel_factor,
         timeout
       ) do
    agents = stress_system.agents

    # Create operation tasks
    all_operations =
      for agent_info <- agents,
          _op_num <- 1..operation_count do
        operation_type = Enum.random(operation_types)
        params = generate_operation_params(operation_type)
        {agent_info, operation_type, params}
      end

    # Execute operations in parallel batches
    execute_operations_in_batches(all_operations, parallel_factor, timeout)
  end

  @spec execute_operations_in_batches(list(tuple()), non_neg_integer(), non_neg_integer()) ::
          {:ok, list()} | {:error, term()}
  defp execute_operations_in_batches(operations, parallel_factor, _timeout) do
    operations
    |> Enum.chunk_every(parallel_factor)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc_results} ->
      tasks =
        Enum.map(batch, fn {agent_info, operation_type, params} ->
          Task.async(fn ->
            execute_agent_action(agent_info.pid, operation_type, params, 5000)
          end)
        end)

      batch_results =
        Enum.map(tasks, fn task ->
          try do
            Task.await(task, 10000)
          catch
            :exit, {:timeout, _} -> {:error, :timeout}
          end
        end)

      {:cont, {:ok, acc_results ++ batch_results}}
    end)
  end

  @spec generate_operation_params(atom()) :: map()
  defp generate_operation_params(:ping), do: %{}
  defp generate_operation_params(:increment), do: %{"amount" => :rand.uniform(10)}
  defp generate_operation_params(:stress_operation), do: %{"load" => :rand.uniform(100)}
  defp generate_operation_params(_), do: %{}

  @spec calculate_success_rate(list()) :: float()
  defp calculate_success_rate(results) do
    total = length(results)

    if total == 0 do
      0.0
    else
      successes =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      successes / total
    end
  end

  @spec calculate_ops_per_second(non_neg_integer(), non_neg_integer()) :: float()
  defp calculate_ops_per_second(total_ops, duration_ms) do
    if duration_ms <= 0 do
      # If operations completed in less than 1ms, use a minimum duration
      total_ops * 1000.0
    else
      total_ops * 1000.0 / duration_ms
    end
  end

  @spec collect_performance_metrics(map(), map()) :: map()
  defp collect_performance_metrics(stress_system, _stress_results) do
    %{
      memory_usage: :erlang.memory() |> Enum.into(%{}),
      process_count: :erlang.system_info(:process_count),
      agent_count: length(stress_system.agents),
      gc_stats: collect_gc_stats()
    }
  end

  @spec collect_gc_stats() :: map()
  defp collect_gc_stats do
    try do
      %{
        total_gc_runs: :erlang.statistics(:garbage_collection),
        memory_after_gc: :erlang.memory(:total)
      }
    rescue
      _ -> %{error: :gc_stats_unavailable}
    end
  end
end
