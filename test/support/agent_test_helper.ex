defmodule AgentTestHelper do
  @moduledoc """
  Specialized test helper for agent lifecycle and behavior testing.

  This module provides utilities for:
  - Agent creation with different isolation levels
  - Agent restart and recovery testing
  - Agent action execution and error handling
  - Agent state management and verification

  ## Usage

  This module builds on `MabeamTestHelper` and provides domain-specific
  testing patterns for agents following OTP best practices.

  ## Example

      # Create isolated agent for destructive testing
      %{agent: agent, pid: pid, name: name} = AgentTestHelper.setup_destructive_agent_test(:demo, 
        capabilities: [:ping, :increment]
      )
      
      # Test agent restart behavior
      {:ok, new_agent} = AgentTestHelper.test_agent_restart(
        %{agent: agent, pid: pid, name: name}, 
        supervisor_pid
      )
      
      # Test complex action scenarios
      test_scenarios = [
        {:ping, %{}, :pong},
        {:increment, %{"amount" => 5}, %{counter: 5}},
        {:unknown_action, %{}, {:error, :unknown_action}}
      ]
      
      :ok = AgentTestHelper.test_agent_action_execution(
        %{agent: agent, pid: pid}, 
        test_scenarios
      )
  """

  import MabeamTestHelper
  require Logger

  # Configuration constants
  @default_timeout 5000
  @restart_timeout 3000

  @doc """
  Creates an isolated agent for destructive testing.

  This function creates an agent with unique naming that can be safely
  killed, restarted, or subjected to destructive operations without
  affecting other tests.

  ## Parameters

  - `agent_type` - The type of agent to create (e.g., :demo)
  - `opts` - Additional options for agent configuration

  ## Options

  - `:capabilities` - List of capabilities for the agent
  - `:initial_state` - Initial state for the agent
  - `:timeout` - Timeout for agent creation (default: #{@default_timeout}ms)
  - `:supervisor` - Custom supervisor PID for restart testing

  ## Returns

  - `%{agent: agent, pid: pid, name: name, supervisor: supervisor_pid}` - Agent info for testing
  - `{:error, reason}` - Failed to create agent

  ## Examples

      agent_info = AgentTestHelper.setup_destructive_agent_test(:demo,
        capabilities: [:ping, :increment, :crash],
        initial_state: %{counter: 0, crash_count: 0}
      )
      
      # Safe to kill this agent - it won't affect other tests
      Process.exit(agent_info.pid, :kill)
  """
  @spec setup_destructive_agent_test(atom(), keyword()) ::
          %{agent: Mabeam.Types.Agent.t(), pid: pid(), name: atom(), supervisor: pid()}
          | {:error, term()}
  def setup_destructive_agent_test(agent_type, opts \\ []) do
    _timeout = Keyword.get(opts, :timeout, @default_timeout)

    case create_test_agent(agent_type, opts) do
      {:ok, agent, pid} ->
        # Get supervisor for restart testing
        supervisor_pid = get_agent_supervisor()

        agent_info = %{
          agent: agent,
          pid: pid,
          name: String.to_atom(agent.id),
          supervisor: supervisor_pid
        }

        Logger.debug("Destructive agent test setup completed",
          agent_id: agent.id,
          pid: inspect(pid),
          supervisor: inspect(supervisor_pid)
        )

        agent_info

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a shared agent for read-only testing.

  This function creates an agent that can be shared across multiple
  read-only tests, optimizing test performance while maintaining isolation.

  ## Parameters

  - `agent_type` - The type of agent to create
  - `opts` - Additional options for agent configuration

  ## Options

  - `:capabilities` - List of capabilities for the agent
  - `:initial_state` - Initial state for the agent
  - `:timeout` - Timeout for agent creation
  - `:shared_name` - Optional shared name for the agent

  ## Returns

  - `%{agent: agent, pid: pid, name: name}` - Agent info for read-only testing
  - `{:error, reason}` - Failed to create agent

  ## Examples

      agent_info = AgentTestHelper.setup_readonly_agent_test(:demo,
        capabilities: [:ping, :get_state],
        shared_name: :demo_readonly_agent
      )
      
      # Safe for multiple tests to read from this agent
      {:ok, result} = execute_agent_action(agent_info.pid, :get_state, %{})
  """
  @spec setup_readonly_agent_test(atom(), keyword()) ::
          %{agent: Mabeam.Types.Agent.t(), pid: pid(), name: atom()} | {:error, term()}
  def setup_readonly_agent_test(agent_type, opts \\ []) do
    shared_name = Keyword.get(opts, :shared_name)

    # Use shared name if provided, otherwise generate unique name
    agent_opts =
      if shared_name do
        Keyword.put(opts, :name, shared_name)
      else
        opts
      end

    case create_test_agent(agent_type, agent_opts) do
      {:ok, agent, pid} ->
        agent_info = %{
          agent: agent,
          pid: pid,
          name: String.to_atom(agent.id)
        }

        Logger.debug("Read-only agent test setup completed",
          agent_id: agent.id,
          pid: inspect(pid),
          shared: not is_nil(shared_name)
        )

        agent_info

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Tests agent restart behavior with proper synchronization.

  This function kills an agent and verifies that it restarts correctly
  under supervision, using proper process monitoring.

  ## Parameters

  - `agent_info` - Agent information from setup functions
  - `supervisor_pid` - The supervisor managing the agent
  - `opts` - Additional options

  ## Options

  - `:timeout` - Timeout for restart verification (default: #{@restart_timeout}ms)
  - `:kill_reason` - Reason for killing the agent (default: :kill)
  - `:verify_state` - Whether to verify agent state after restart (default: true)

  ## Returns

  - `{:ok, new_agent_info}` - Agent restarted successfully
  - `{:error, reason}` - Restart failed or timed out

  ## Examples

      {:ok, new_agent_info} = AgentTestHelper.test_agent_restart(
        agent_info, 
        supervisor_pid,
        timeout: 5000,
        kill_reason: :shutdown
      )
      
      # Verify the new agent is different from the old one
      assert new_agent_info.pid != agent_info.pid
      assert Process.alive?(new_agent_info.pid)
  """
  @spec test_agent_restart(map(), pid(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def test_agent_restart(agent_info, supervisor_pid, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @restart_timeout)
    kill_reason = Keyword.get(opts, :kill_reason, :kill)
    verify_state = Keyword.get(opts, :verify_state, true)

    original_pid = agent_info.pid
    agent_id = agent_info.agent.id

    Logger.debug("Starting agent restart test",
      agent_id: agent_id,
      original_pid: inspect(original_pid),
      kill_reason: kill_reason
    )

    # Monitor the original process
    ref = Process.monitor(original_pid)

    # Kill the original process
    Process.exit(original_pid, kill_reason)

    # Wait for original process to die
    receive do
      {:DOWN, ^ref, :process, ^original_pid, actual_reason} ->
        Logger.debug("Original agent process terminated",
          agent_id: agent_id,
          reason: actual_reason
        )

        # Wait for supervisor to restart the agent
        case wait_for_agent_restart(agent_id, original_pid, timeout) do
          {:ok, new_pid} ->
            # Get the new agent information
            case Mabeam.get_agent(agent_id) do
              {:ok, new_agent} ->
                new_agent_info = %{
                  agent: new_agent,
                  pid: new_pid,
                  name: agent_info.name,
                  supervisor: supervisor_pid
                }

                # Verify state if requested
                if verify_state do
                  case verify_agent_restart_state(new_agent_info, agent_info) do
                    :ok ->
                      Logger.debug("Agent restart test completed successfully",
                        agent_id: agent_id,
                        new_pid: inspect(new_pid)
                      )

                      {:ok, new_agent_info}

                    {:error, reason} ->
                      {:error, {:state_verification_failed, reason}}
                  end
                else
                  {:ok, new_agent_info}
                end

              {:error, reason} ->
                {:error, {:agent_not_found_after_restart, reason}}
            end

          {:error, reason} ->
            {:error, {:restart_timeout, reason}}
        end
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, {:original_process_termination_timeout, timeout}}
    end
  end

  @doc """
  Tests agent action execution with comprehensive error handling.

  This function executes a series of test scenarios against an agent,
  verifying both successful operations and proper error handling.

  ## Parameters

  - `agent_info` - Agent information from setup functions
  - `test_scenarios` - List of test scenarios to execute
  - `opts` - Additional options

  ## Test Scenario Format

  Each scenario is a tuple: `{action, params, expected_result}`
  - `action` - The action atom to execute
  - `params` - Parameters map for the action
  - `expected_result` - Expected result pattern or exact match

  ## Options

  - `:timeout` - Timeout for each action (default: #{@default_timeout}ms)
  - `:verify_state` - Whether to verify agent state after each action
  - `:continue_on_error` - Whether to continue testing after errors (default: false)

  ## Returns

  - `:ok` - All scenarios executed successfully
  - `{:error, {:scenario_failed, scenario, reason}}` - Scenario failed

  ## Examples

      test_scenarios = [
        {:ping, %{}, fn result -> result.response == :pong end},
        {:increment, %{"amount" => 5}, %{counter: 5}},
        {:unknown_action, %{}, {:error, :unknown_action}},
        {:get_state, %{}, fn result -> is_map(result.state) end}
      ]
      
      :ok = AgentTestHelper.test_agent_action_execution(agent_info, test_scenarios)
  """
  @spec test_agent_action_execution(map(), list(tuple()), keyword()) ::
          :ok | {:error, term()}
  def test_agent_action_execution(agent_info, test_scenarios, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    verify_state = Keyword.get(opts, :verify_state, false)
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    Logger.debug("Starting agent action execution test",
      agent_id: agent_info.agent.id,
      scenario_count: length(test_scenarios)
    )

    execute_scenarios(agent_info, test_scenarios, timeout, verify_state, continue_on_error, [])
  end

  @doc """
  Verifies agent state consistency after operations.

  This function checks that an agent's state matches expected patterns
  and maintains consistency across operations.

  ## Parameters

  - `agent_info` - Agent information from setup functions
  - `expected_state` - Expected state pattern or validation function
  - `opts` - Additional options

  ## Options

  - `:timeout` - Timeout for state retrieval (default: #{@default_timeout}ms)
  - `:strict` - Whether to use strict equality check (default: false)
  - `:fields` - Specific fields to check (default: all fields)

  ## Returns

  - `:ok` - State verification passed
  - `{:error, {:state_mismatch, expected, actual}}` - State verification failed

  ## Examples

      # Verify specific state values
      :ok = AgentTestHelper.verify_agent_state_consistency(agent_info, %{
        counter: 10,
        messages: []
      })
      
      # Use validation function
      :ok = AgentTestHelper.verify_agent_state_consistency(agent_info, fn state ->
        state.counter >= 0 and is_list(state.messages)
      end)
  """
  @spec verify_agent_state_consistency(map(), term(), keyword()) ::
          :ok | {:error, term()}
  def verify_agent_state_consistency(agent_info, expected_state, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    strict = Keyword.get(opts, :strict, false)
    fields = Keyword.get(opts, :fields, :all)

    case execute_agent_action(agent_info.pid, :get_state, %{}, timeout) do
      {:ok, result} ->
        actual_state = result.state

        case verify_state_match(actual_state, expected_state, strict, fields) do
          :ok ->
            Logger.debug("Agent state verification passed",
              agent_id: agent_info.agent.id
            )

            :ok

          {:error, reason} ->
            Logger.debug("Agent state verification failed",
              agent_id: agent_info.agent.id,
              reason: reason,
              expected: inspect(expected_state),
              actual: inspect(actual_state)
            )

            {:error, {:state_mismatch, expected_state, actual_state, reason}}
        end

      {:error, reason} ->
        {:error, {:state_retrieval_failed, reason}}
    end
  end

  @doc """
  Tests agent error recovery scenarios.

  This function tests how agents handle and recover from various
  error conditions, ensuring system resilience.

  ## Parameters

  - `agent_info` - Agent information from setup functions
  - `error_scenarios` - List of error scenarios to test
  - `opts` - Additional options

  ## Error Scenario Format

  Each scenario is a map with:
  - `:trigger` - Function to trigger the error
  - `:expected_error` - Expected error pattern
  - `:recovery_action` - Optional recovery action
  - `:verify_recovery` - Optional recovery verification function

  ## Options

  - `:timeout` - Timeout for each scenario (default: #{@default_timeout}ms)
  - `:continue_on_failure` - Whether to continue after failed recovery

  ## Returns

  - `:ok` - All error scenarios handled correctly
  - `{:error, {:error_scenario_failed, scenario, reason}}` - Scenario failed

  ## Examples

      error_scenarios = [
        %{
          trigger: fn agent_info -> 
            execute_agent_action(agent_info.pid, :unknown_action, %{})
          end,
          expected_error: {:error, :unknown_action},
          verify_recovery: fn agent_info ->
            execute_agent_action(agent_info.pid, :ping, %{})
          end
        }
      ]
      
      :ok = AgentTestHelper.test_agent_error_recovery(agent_info, error_scenarios)
  """
  @spec test_agent_error_recovery(map(), list(map()), keyword()) ::
          :ok | {:error, term()}
  def test_agent_error_recovery(agent_info, error_scenarios, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    continue_on_failure = Keyword.get(opts, :continue_on_failure, false)

    Logger.debug("Starting agent error recovery test",
      agent_id: agent_info.agent.id,
      scenario_count: length(error_scenarios)
    )

    execute_error_scenarios(agent_info, error_scenarios, timeout, continue_on_failure, [])
  end

  # Private helper functions

  @spec get_agent_supervisor() :: pid()
  defp get_agent_supervisor do
    # Get the DynamicSupervisor that manages agents
    case Process.whereis(Mabeam.Foundation.AgentSupervisor) do
      nil ->
        # If not found, get the main supervisor
        Process.whereis(Mabeam.Foundation.Supervisor)

      pid when is_pid(pid) ->
        pid
    end
  end

  @spec wait_for_agent_restart(binary(), pid(), non_neg_integer()) ::
          {:ok, pid()} | {:error, term()}
  defp wait_for_agent_restart(agent_id, original_pid, timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn loop ->
      case Mabeam.get_agent_process(agent_id) do
        {:ok, new_pid} when new_pid != original_pid ->
          if Process.alive?(new_pid) do
            {:ok, new_pid}
          else
            # Process exists but is not alive, continue waiting
            check_timeout_and_continue(start_time, timeout, loop)
          end

        {:ok, ^original_pid} ->
          # Still the original process, continue waiting
          check_timeout_and_continue(start_time, timeout, loop)

        {:error, :not_found} ->
          # Agent not yet registered, continue waiting
          check_timeout_and_continue(start_time, timeout, loop)

        {:error, reason} ->
          {:error, reason}
      end
    end

    wait_loop.(wait_loop)
  end

  @spec check_timeout_and_continue(integer(), non_neg_integer(), function()) ::
          {:ok, term()} | {:error, :timeout}
  defp check_timeout_and_continue(start_time, timeout, loop_fn) do
    if System.monotonic_time(:millisecond) - start_time > timeout do
      {:error, :timeout}
    else
      loop_fn.(loop_fn)
    end
  end

  @spec verify_agent_restart_state(map(), map()) :: :ok | {:error, term()}
  defp verify_agent_restart_state(new_agent_info, _original_agent_info) do
    case execute_agent_action(new_agent_info.pid, :get_state, %{}) do
      {:ok, result} ->
        # Basic verification - agent should be functional
        if is_map(result.state) do
          :ok
        else
          {:error, :invalid_state_structure}
        end

      {:error, reason} ->
        {:error, {:state_check_failed, reason}}
    end
  end

  @spec execute_scenarios(map(), list(tuple()), non_neg_integer(), boolean(), boolean(), list()) ::
          :ok | {:error, term()}
  defp execute_scenarios(_agent_info, [], _timeout, _verify_state, _continue_on_error, results) do
    # All scenarios completed successfully
    Logger.debug("All agent action scenarios completed",
      total_results: length(results)
    )

    :ok
  end

  defp execute_scenarios(
         agent_info,
         [scenario | remaining],
         timeout,
         verify_state,
         continue_on_error,
         results
       ) do
    case execute_single_scenario(agent_info, scenario, timeout, verify_state) do
      :ok ->
        execute_scenarios(agent_info, remaining, timeout, verify_state, continue_on_error, [
          :ok | results
        ])

      {:error, reason} ->
        if continue_on_error do
          Logger.warning("Scenario failed but continuing",
            scenario: inspect(scenario),
            reason: reason
          )

          execute_scenarios(agent_info, remaining, timeout, verify_state, continue_on_error, [
            reason | results
          ])
        else
          {:error, {:scenario_failed, scenario, reason}}
        end
    end
  end

  @spec execute_single_scenario(map(), tuple(), non_neg_integer(), boolean()) ::
          {:ok, term()} | {:error, term()}
  defp execute_single_scenario(agent_info, {action, params, expected}, timeout, verify_state) do
    case execute_agent_action(agent_info.pid, action, params, timeout) do
      result ->
        case verify_scenario_result(result, expected) do
          :ok ->
            if verify_state do
              case verify_agent_state_consistency(agent_info, fn _state -> true end) do
                :ok -> :ok
                {:error, reason} -> {:error, {:state_verification_failed, reason}}
              end
            else
              :ok
            end

          {:error, reason} ->
            {:error, {:result_verification_failed, reason, expected, result}}
        end
    end
  end

  @spec verify_scenario_result(term(), term()) :: :ok | {:error, term()}
  defp verify_scenario_result(actual, expected) when is_function(expected) do
    if expected.(actual) do
      :ok
    else
      {:error, :function_validation_failed}
    end
  end

  defp verify_scenario_result(actual, expected) do
    if actual == expected do
      :ok
    else
      {:error, :exact_match_failed}
    end
  end

  @spec verify_state_match(map(), term(), boolean(), atom() | list()) :: :ok | {:error, term()}
  defp verify_state_match(actual_state, expected_state, _strict, _fields)
       when is_function(expected_state) do
    if expected_state.(actual_state) do
      :ok
    else
      {:error, :function_validation_failed}
    end
  end

  defp verify_state_match(actual_state, expected_state, strict, :all)
       when is_map(expected_state) do
    if strict do
      if actual_state == expected_state do
        :ok
      else
        {:error, :strict_equality_failed}
      end
    else
      # Check that all expected fields match
      missing_or_mismatched =
        Enum.filter(expected_state, fn {key, expected_value} ->
          case Map.get(actual_state, key) do
            ^expected_value -> false
            _ -> true
          end
        end)

      if Enum.empty?(missing_or_mismatched) do
        :ok
      else
        {:error, {:field_mismatch, missing_or_mismatched}}
      end
    end
  end

  defp verify_state_match(actual_state, expected_state, _strict, fields)
       when is_list(fields) and is_map(expected_state) do
    # Check only specified fields
    missing_or_mismatched =
      Enum.filter(fields, fn field ->
        expected_value = Map.get(expected_state, field)
        actual_value = Map.get(actual_state, field)
        expected_value != actual_value
      end)

    if Enum.empty?(missing_or_mismatched) do
      :ok
    else
      {:error, {:specified_field_mismatch, missing_or_mismatched}}
    end
  end

  defp verify_state_match(_actual_state, expected_state, _strict, _fields) do
    {:error, {:unsupported_expected_state_format, expected_state}}
  end

  @spec execute_error_scenarios(map(), list(map()), non_neg_integer(), boolean(), list()) ::
          :ok | {:error, term()}
  defp execute_error_scenarios(_agent_info, [], _timeout, _continue_on_failure, results) do
    Logger.debug("All error recovery scenarios completed",
      total_results: length(results)
    )

    :ok
  end

  defp execute_error_scenarios(
         agent_info,
         [scenario | remaining],
         timeout,
         continue_on_failure,
         results
       ) do
    case execute_error_scenario(agent_info, scenario, timeout) do
      :ok ->
        execute_error_scenarios(agent_info, remaining, timeout, continue_on_failure, [
          :ok | results
        ])

      {:error, reason} ->
        if continue_on_failure do
          Logger.warning("Error scenario failed but continuing",
            scenario: inspect(scenario),
            reason: reason
          )

          execute_error_scenarios(agent_info, remaining, timeout, continue_on_failure, [
            reason | results
          ])
        else
          {:error, {:error_scenario_failed, scenario, reason}}
        end
    end
  end

  @spec execute_error_scenario(map(), map(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  defp execute_error_scenario(agent_info, scenario, timeout) do
    trigger_fn = Map.get(scenario, :trigger)
    expected_error = Map.get(scenario, :expected_error)
    recovery_action = Map.get(scenario, :recovery_action)
    verify_recovery = Map.get(scenario, :verify_recovery)

    # Trigger the error
    case trigger_fn.(agent_info) do
      result ->
        # Verify the error matches expectation
        case verify_scenario_result(result, expected_error) do
          :ok ->
            # Execute recovery action if provided
            case execute_recovery_action(agent_info, recovery_action, timeout) do
              :ok ->
                # Verify recovery if provided
                execute_recovery_verification(agent_info, verify_recovery, timeout)

              {:error, reason} ->
                {:error, {:recovery_action_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:error_verification_failed, reason}}
        end
    end
  end

  @spec execute_recovery_action(map(), term(), non_neg_integer()) :: :ok | {:error, term()}
  defp execute_recovery_action(_agent_info, nil, _timeout), do: :ok

  defp execute_recovery_action(agent_info, recovery_action, _timeout)
       when is_function(recovery_action) do
    try do
      case recovery_action.(agent_info) do
        :ok -> :ok
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
        _other -> :ok
      end
    rescue
      error -> {:error, {:recovery_action_exception, error}}
    catch
      :exit, reason -> {:error, {:recovery_action_exit, reason}}
    end
  end

  defp execute_recovery_action(_agent_info, recovery_action, _timeout) do
    {:error, {:unsupported_recovery_action, recovery_action}}
  end

  @spec execute_recovery_verification(map(), term(), non_neg_integer()) :: :ok | {:error, term()}
  defp execute_recovery_verification(_agent_info, nil, _timeout), do: :ok

  defp execute_recovery_verification(agent_info, verify_recovery, _timeout)
       when is_function(verify_recovery) do
    try do
      case verify_recovery.(agent_info) do
        :ok -> :ok
        {:ok, _result} -> :ok
        true -> :ok
        false -> {:error, :recovery_verification_failed}
        {:error, reason} -> {:error, reason}
        _other -> :ok
      end
    rescue
      error -> {:error, {:recovery_verification_exception, error}}
    catch
      :exit, reason -> {:error, {:recovery_verification_exit, reason}}
    end
  end

  defp execute_recovery_verification(_agent_info, verify_recovery, _timeout) do
    {:error, {:unsupported_recovery_verification, verify_recovery}}
  end
end
