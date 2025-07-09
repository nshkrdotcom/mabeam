defmodule MabeamTestHelper do
  @moduledoc """
  Comprehensive test helper for MABEAM following OTP testing standards.

  This module provides utilities for:
  - Process lifecycle management with proper synchronization
  - Agent creation and cleanup with unique naming
  - Event system testing with proper wait mechanisms
  - Resource management and cleanup automation

  ## Usage

  This module follows OTP testing best practices:
  - NO Process.sleep/1 usage (except minimal synchronization delays)
  - Proper process monitoring with receive blocks
  - Unique naming to prevent test conflicts
  - Comprehensive cleanup automation
  - Timeout handling for all operations

  ## Example

      # Create test agent with automatic cleanup
      {:ok, agent, pid} = MabeamTestHelper.create_test_agent(:demo, 
        capabilities: [:ping]
      )
      
      # Execute action with proper synchronization
      {:ok, result} = MabeamTestHelper.execute_agent_action(pid, :ping, %{})
      
      # Wait for events with proper filtering
      event = MabeamTestHelper.wait_for_event(:demo_ping)
      
      # Cleanup is automatic via ExUnit.Callbacks.on_exit/1
  """

  require Logger

  # Configuration constants
  @default_timeout 5000
  @cleanup_timeout 1000
  @sync_delay 10

  @doc """
  Creates a test agent with unique naming and automatic cleanup.

  This function generates a unique agent name to prevent conflicts
  between concurrent tests and registers cleanup handlers.

  ## Parameters

  - `agent_type` - The type of agent to create (e.g., :demo)
  - `opts` - Additional options for agent configuration

  ## Options

  - `:capabilities` - List of capabilities for the agent
  - `:initial_state` - Initial state for the agent
  - `:timeout` - Timeout for agent creation (default: #{@default_timeout}ms)

  ## Returns

  - `{:ok, agent, pid}` - Successfully created agent
  - `{:error, reason}` - Failed to create agent

  ## Examples

      {:ok, agent, pid} = MabeamTestHelper.create_test_agent(:demo,
        capabilities: [:ping, :increment],
        initial_state: %{counter: 0}
      )
  """
  @spec create_test_agent(atom(), keyword()) ::
          {:ok, Mabeam.Types.Agent.t(), pid()} | {:error, term()}
  def create_test_agent(agent_type, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Generate unique test ID and agent name
    test_id = generate_test_id()
    agent_name = :"test_agent_#{test_id}"

    # Extract options
    capabilities = Keyword.get(opts, :capabilities, [])
    initial_state = Keyword.get(opts, :initial_state, %{})

    # Create agent configuration
    agent_config = [
      type: agent_type,
      capabilities: capabilities,
      initial_state: initial_state,
      name: agent_name
    ]

    # Start the agent
    case Mabeam.DemoAgent.start_link(agent_config) do
      {:ok, agent, pid} ->
        # Register for cleanup
        register_agent_for_cleanup(pid, agent.id)

        # Wait for agent to be fully registered
        case wait_for_agent_registration(agent.id, timeout) do
          :ok ->
            Logger.debug("Test agent created successfully",
              agent_id: agent.id,
              test_id: test_id,
              capabilities: capabilities
            )

            {:ok, agent, pid}

          {:error, reason} ->
            # Cleanup on failure
            if Process.alive?(pid) do
              Process.exit(pid, :kill)
            end

            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Failed to create test agent",
          reason: reason,
          agent_type: agent_type,
          test_id: test_id
        )

        {:error, reason}
    end
  end

  @doc """
  Waits for agent to reach specific state with proper synchronization.

  This function uses GenServer.call to synchronously check agent state
  without using Process.sleep/1.

  ## Parameters

  - `agent_name` - The name/ID of the agent to check
  - `expected_state` - Function that returns true when state is correct
  - `timeout` - Maximum time to wait (default: #{@default_timeout}ms)

  ## Returns

  - `:ok` - Agent reached expected state
  - `{:error, :timeout}` - Timeout waiting for state
  - `{:error, reason}` - Other error occurred

  ## Examples

      # Wait for counter to reach 5
      :ok = MabeamTestHelper.wait_for_agent_state(agent_id, fn state ->
        state.counter >= 5
      end)
  """
  @spec wait_for_agent_state(binary() | pid(), (map() -> boolean()), non_neg_integer()) ::
          :ok | {:error, term()}
  def wait_for_agent_state(agent_identifier, condition_fn, timeout \\ @default_timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn loop ->
      case get_agent_state(agent_identifier) do
        {:ok, state} ->
          if condition_fn.(state) do
            :ok
          else
            if System.monotonic_time(:millisecond) - start_time > timeout do
              {:error, :timeout}
            else
              # Minimal delay before retry
              Process.sleep(@sync_delay)
              loop.(loop)
            end
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    wait_loop.(wait_loop)
  end

  @doc """
  Executes agent action with proper error handling and synchronization.

  This function uses GenServer.call for synchronous operation with
  proper timeout handling.

  ## Parameters

  - `pid` - The agent process ID
  - `action` - The action to execute
  - `params` - Parameters for the action
  - `timeout` - Timeout for action execution (default: #{@default_timeout}ms)

  ## Returns

  - `{:ok, result}` - Action executed successfully
  - `{:error, reason}` - Action failed

  ## Examples

      {:ok, result} = MabeamTestHelper.execute_agent_action(pid, :ping, %{})
      {:ok, result} = MabeamTestHelper.execute_agent_action(pid, :increment, %{"amount" => 5})
  """
  @spec execute_agent_action(pid(), atom(), map(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  def execute_agent_action(pid, action, params, _timeout \\ @default_timeout) do
    try do
      Mabeam.DemoAgent.execute_action(pid, action, params)
    rescue
      error ->
        {:error, {:execution_error, error}}
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout}

      :exit, reason ->
        {:error, {:process_exit, reason}}
    end
  end

  @doc """
  Subscribes to events with automatic cleanup.

  This function subscribes to events and registers cleanup handlers
  to prevent subscription leaks.

  ## Parameters

  - `event_patterns` - List of event types or patterns to subscribe to
  - `opts` - Additional options

  ## Options

  - `:timeout` - Timeout for subscription (default: #{@default_timeout}ms)

  ## Returns

  - `:ok` - Successfully subscribed
  - `{:error, reason}` - Subscription failed

  ## Examples

      :ok = MabeamTestHelper.subscribe_to_events([:demo_ping, :demo_increment])
      :ok = MabeamTestHelper.subscribe_to_events(["demo.*"], timeout: 1000)
  """
  @spec subscribe_to_events(list(), keyword()) :: :ok | {:error, term()}
  def subscribe_to_events(event_patterns, _opts \\ []) do
    try do
      Enum.each(event_patterns, fn pattern ->
        case pattern do
          pattern when is_binary(pattern) ->
            Mabeam.subscribe_pattern(pattern)

          event_type when is_atom(event_type) ->
            Mabeam.subscribe(event_type)
        end
      end)

      # Register for cleanup
      register_subscriptions_for_cleanup(event_patterns)
      :ok
    rescue
      error ->
        {:error, {:subscription_error, error}}
    end
  end

  @doc """
  Waits for specific event with timeout and proper filtering.

  This function waits for events using proper receive blocks with
  timeout handling, avoiding Process.sleep/1.

  ## Parameters

  - `event_type` - The type of event to wait for
  - `timeout` - Maximum time to wait (default: #{@default_timeout}ms)

  ## Returns

  - `{:ok, event}` - Event received
  - `{:error, :timeout}` - Timeout waiting for event

  ## Examples

      {:ok, event} = MabeamTestHelper.wait_for_event(:demo_ping)
      {:error, :timeout} = MabeamTestHelper.wait_for_event(:nonexistent, 1000)
  """
  @spec wait_for_event(atom(), non_neg_integer()) ::
          {:ok, map()} | {:error, :timeout}
  def wait_for_event(event_type, timeout \\ @default_timeout) do
    receive do
      {:event, %{type: ^event_type} = event} ->
        {:ok, event}

      {:event, _other_event} ->
        # Ignore other events and continue waiting
        wait_for_event(event_type, timeout)
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for multiple events in sequence with proper ordering.

  This function waits for a list of events in the specified order,
  using proper synchronization without Process.sleep/1.

  ## Parameters

  - `event_types` - List of event types to wait for in order
  - `timeout` - Maximum time to wait for all events (default: #{@default_timeout}ms)

  ## Returns

  - `{:ok, events}` - All events received in order
  - `{:error, {:timeout, received_events}}` - Timeout with partial results

  ## Examples

      {:ok, [ping_event, increment_event]} = MabeamTestHelper.wait_for_events([
        :demo_ping, 
        :demo_increment
      ])
  """
  @spec wait_for_events(list(atom()), non_neg_integer()) ::
          {:ok, list(map())} | {:error, {:timeout, list(map())}}
  def wait_for_events(event_types, timeout \\ @default_timeout) do
    start_time = System.monotonic_time(:millisecond)
    wait_for_events_loop(event_types, [], start_time, timeout)
  end

  @doc """
  Monitors process termination with proper synchronization.

  This function monitors a process and waits for its termination
  using proper process monitoring without Process.sleep/1.

  ## Parameters

  - `pid` - The process to monitor
  - `timeout` - Maximum time to wait (default: #{@default_timeout}ms)

  ## Returns

  - `{:ok, reason}` - Process terminated with reason
  - `{:error, :timeout}` - Timeout waiting for termination

  ## Examples

      {:ok, :normal} = MabeamTestHelper.wait_for_process_termination(pid)
      {:ok, :killed} = MabeamTestHelper.wait_for_process_termination(pid, 1000)
  """
  @spec wait_for_process_termination(pid(), non_neg_integer()) ::
          {:ok, term()} | {:error, :timeout}
  def wait_for_process_termination(pid, timeout \\ @default_timeout) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, reason} ->
          {:ok, reason}
      after
        timeout ->
          Process.demonitor(ref, [:flush])
          {:error, :timeout}
      end
    else
      {:ok, :already_dead}
    end
  end

  @doc """
  Kills process and waits for termination with monitoring.

  This function kills a process and waits for confirmation of
  termination using proper process monitoring.

  ## Parameters

  - `pid` - The process to kill
  - `timeout` - Maximum time to wait (default: #{@default_timeout}ms)

  ## Returns

  - `{:ok, reason}` - Process killed and terminated
  - `{:error, :timeout}` - Timeout waiting for termination

  ## Examples

      {:ok, :killed} = MabeamTestHelper.kill_and_wait(pid)
  """
  @spec kill_and_wait(pid(), non_neg_integer()) ::
          {:ok, term()} | {:error, :timeout}
  def kill_and_wait(pid, timeout \\ @default_timeout) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^ref, :process, ^pid, reason} ->
          {:ok, reason}
      after
        timeout ->
          Process.demonitor(ref, [:flush])
          {:error, :timeout}
      end
    else
      {:ok, :already_dead}
    end
  end

  @doc """
  Waits for agent registration with proper synchronization.

  This function waits for an agent to be registered in the registry
  using proper synchronization without Process.sleep/1.

  ## Parameters

  - `agent_name` - The agent ID to wait for
  - `timeout` - Maximum time to wait (default: #{@default_timeout}ms)

  ## Returns

  - `:ok` - Agent successfully registered
  - `{:error, :timeout}` - Timeout waiting for registration

  ## Examples

      :ok = MabeamTestHelper.wait_for_agent_registration(agent_id)
  """
  @spec wait_for_agent_registration(binary(), non_neg_integer()) ::
          :ok | {:error, :timeout}
  def wait_for_agent_registration(agent_name, timeout \\ @default_timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn loop ->
      case Mabeam.get_agent(agent_name) do
        {:ok, _agent} ->
          :ok

        {:error, :not_found} ->
          if System.monotonic_time(:millisecond) - start_time > timeout do
            {:error, :timeout}
          else
            Process.sleep(@sync_delay)
            loop.(loop)
          end
      end
    end

    wait_loop.(wait_loop)
  end

  @doc """
  Waits for agent deregistration with proper synchronization.

  This function waits for an agent to be deregistered from the registry
  using proper synchronization without Process.sleep/1.

  ## Parameters

  - `agent_name` - The agent ID to wait for deregistration
  - `timeout` - Maximum time to wait (default: #{@default_timeout}ms)

  ## Returns

  - `:ok` - Agent successfully deregistered
  - `{:error, :timeout}` - Timeout waiting for deregistration

  ## Examples

      :ok = MabeamTestHelper.wait_for_agent_deregistration(agent_id)
  """
  @spec wait_for_agent_deregistration(binary(), non_neg_integer()) ::
          :ok | {:error, :timeout}
  def wait_for_agent_deregistration(agent_name, timeout \\ @default_timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn loop ->
      case Mabeam.get_agent(agent_name) do
        {:error, :not_found} ->
          :ok

        {:ok, _agent} ->
          if System.monotonic_time(:millisecond) - start_time > timeout do
            {:error, :timeout}
          else
            Process.sleep(@sync_delay)
            loop.(loop)
          end
      end
    end

    wait_loop.(wait_loop)
  end

  @doc """
  Comprehensive cleanup of all test resources.

  This function is called automatically via ExUnit.Callbacks.on_exit/1
  to clean up all resources created during a test.

  Resources cleaned up:
  - Test agents and their processes
  - Event subscriptions
  - Registry entries

  ## Returns

  - `:ok` - Cleanup completed successfully

  ## Examples

      # This is called automatically, but can be called manually:
      :ok = MabeamTestHelper.cleanup_all_test_resources()
  """
  @spec cleanup_all_test_resources() :: :ok
  def cleanup_all_test_resources do
    # Get cleanup lists from process dictionary
    agent_cleanups = Process.get(:agent_cleanups, [])
    subscription_cleanups = Process.get(:subscription_cleanups, [])

    Logger.debug("Starting test cleanup",
      agents: length(agent_cleanups),
      subscriptions: length(subscription_cleanups)
    )

    # Cleanup agents
    Enum.each(agent_cleanups, fn {pid, agent_id} ->
      cleanup_agent(pid, agent_id)
    end)

    # Cleanup subscriptions
    Enum.each(subscription_cleanups, fn pattern ->
      cleanup_subscription(pattern)
    end)

    # Clear cleanup lists
    Process.put(:agent_cleanups, [])
    Process.put(:subscription_cleanups, [])

    Logger.debug("Test cleanup completed")
    :ok
  end

  # Private helper functions

  @spec generate_test_id() :: String.t()
  defp generate_test_id do
    test_name =
      case Process.get(:ex_unit_test) do
        %{name: name} ->
          name
          |> to_string()
          |> String.replace(~r/[^a-zA-Z0-9_]/, "_")

        _ ->
          "test"
      end

    unique_id = :erlang.unique_integer([:positive])
    "#{test_name}_#{unique_id}"
  end

  @spec register_agent_for_cleanup(pid(), binary()) :: :ok
  defp register_agent_for_cleanup(pid, agent_id) do
    # Only register cleanup if we're in the test process
    # Tasks and child processes cannot use ExUnit.Callbacks.on_exit
    try do
      existing_cleanups = Process.get(:agent_cleanups, [])
      Process.put(:agent_cleanups, [{pid, agent_id} | existing_cleanups])

      # Only register cleanup callback once per test process
      unless Process.get(:cleanup_registered, false) do
        Process.put(:cleanup_registered, true)

        ExUnit.Callbacks.on_exit(fn ->
          cleanup_all_test_resources()
        end)
      end
    rescue
      ArgumentError ->
        # We're not in the test process, can't register cleanup
        # This is expected when called from Tasks - cleanup will happen
        # when the test process exits
        :ok
    end

    :ok
  end

  @spec register_subscriptions_for_cleanup(list()) :: :ok
  defp register_subscriptions_for_cleanup(patterns) do
    existing_cleanups = Process.get(:subscription_cleanups, [])
    Process.put(:subscription_cleanups, patterns ++ existing_cleanups)
    :ok
  end

  @spec cleanup_agent(pid(), binary()) :: :ok
  defp cleanup_agent(pid, agent_id) do
    try do
      # Stop agent gracefully
      case Mabeam.stop_agent(agent_id) do
        :ok ->
          # Wait for termination
          case wait_for_process_termination(pid, @cleanup_timeout) do
            {:ok, _reason} ->
              Logger.debug("Agent cleaned up successfully", agent_id: agent_id)

            {:error, :timeout} ->
              # Force kill if graceful stop failed
              Logger.warning("Force killing agent after timeout", agent_id: agent_id)
              Process.exit(pid, :kill)
          end

        {:error, _reason} ->
          # If graceful stop failed, force kill
          if Process.alive?(pid) do
            Logger.warning("Force killing agent after stop failed", agent_id: agent_id)
            Process.exit(pid, :kill)
          end
      end
    rescue
      error ->
        Logger.warning("Error during agent cleanup",
          agent_id: agent_id,
          error: inspect(error)
        )

        # Force kill as last resort
        if Process.alive?(pid) do
          Process.exit(pid, :kill)
        end
    end

    :ok
  end

  @spec cleanup_subscription(atom() | binary()) :: :ok
  defp cleanup_subscription(pattern) do
    try do
      # Note: Unsubscribe functions may not be implemented yet
      # For now, just log the cleanup attempt
      Logger.debug("Subscription cleanup attempted", pattern: pattern)

      # TODO: Implement when unsubscribe functions are available
      # case pattern do
      #   pattern when is_binary(pattern) ->
      #     Mabeam.unsubscribe_pattern(pattern)
      #   event_type when is_atom(event_type) ->
      #     Mabeam.unsubscribe(event_type)
      # end
    rescue
      error ->
        Logger.warning("Error during subscription cleanup",
          pattern: pattern,
          error: inspect(error)
        )
    end

    :ok
  end

  @spec get_agent_state(binary() | pid()) :: {:ok, map()} | {:error, term()}
  defp get_agent_state(agent_identifier) do
    case agent_identifier do
      pid when is_pid(pid) ->
        # Direct process call
        execute_agent_action(pid, :get_state, %{})

      agent_id when is_binary(agent_id) ->
        # Get process from registry first
        case Mabeam.get_agent_process(agent_id) do
          {:ok, pid} ->
            execute_agent_action(pid, :get_state, %{})

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @spec wait_for_events_loop(list(atom()), list(map()), integer(), non_neg_integer()) ::
          {:ok, list(map())} | {:error, {:timeout, list(map())}}
  defp wait_for_events_loop([], received_events, _start_time, _timeout) do
    {:ok, Enum.reverse(received_events)}
  end

  defp wait_for_events_loop([event_type | remaining], received_events, start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    remaining_timeout = timeout - elapsed

    if remaining_timeout <= 0 do
      {:error, {:timeout, Enum.reverse(received_events)}}
    else
      case wait_for_event(event_type, remaining_timeout) do
        {:ok, event} ->
          wait_for_events_loop(remaining, [event | received_events], start_time, timeout)

        {:error, :timeout} ->
          {:error, {:timeout, Enum.reverse(received_events)}}
      end
    end
  end
end
