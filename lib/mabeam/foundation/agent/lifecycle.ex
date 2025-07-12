defmodule Mabeam.Foundation.Agent.Lifecycle do
  @moduledoc """
  Manages agent lifecycle from creation to termination.

  This module handles the complete lifecycle of agents including:
  - Creation and initialization
  - Registration in the registry
  - Lifecycle state transitions
  - Graceful shutdown
  - Cleanup on termination
  """

  require Logger

  alias Mabeam.Types.Agent, as: AgentTypes

  # Performance constants
  @default_start_timeout 5000
  @default_stop_timeout 3000
  @max_restart_attempts 3
  alias Mabeam.Types.Agent.Agent
  alias Mabeam.Types.ID
  alias Mabeam.Foundation.Registry
  alias Mabeam.Foundation.Communication.EventBus

  @type agent_module :: module()
  @type agent_config :: keyword()
  @type lifecycle_result :: {:ok, Agent.t(), pid()} | {:error, term()}

  @doc """
  Starts a new agent with the given configuration.

  ## Parameters

  - `agent_module`: The module implementing the agent behavior
  - `config`: Configuration options for the agent

  ## Options

  - `:id` - Custom agent ID (defaults to generated UUID)
  - `:type` - Agent type (defaults to module name)
  - `:capabilities` - List of capabilities (defaults to empty list)
  - `:metadata` - Additional metadata (defaults to empty map)
  - `:initial_state` - Initial state for the agent (defaults to empty map)

  ## Returns

  - `{:ok, agent, pid}` - Agent started successfully
  - `{:error, reason}` - Failed to start agent
  """
  @spec start_agent(agent_module(), agent_config()) :: lifecycle_result()
  @spec stop_agent(binary(), term()) :: :ok | {:error, term()}
  @spec restart_agent(binary(), agent_config()) :: lifecycle_result()
  @spec update_lifecycle_state(binary(), AgentTypes.lifecycle_state()) :: {:ok, Agent.t()} | {:error, term()}
  @spec get_lifecycle_state(binary()) :: {:ok, AgentTypes.lifecycle_state()} | {:error, :not_found}
  def start_agent(agent_module, config \\ []) when is_atom(agent_module) do
    # Generate or use provided ID
    agent_id =
      case Keyword.get(config, :id) do
        nil -> ID.agent_id() |> ID.unwrap()
        custom_id when is_binary(custom_id) -> custom_id
        other -> "#{other}"
      end

    # Create agent data structure
    now = DateTime.utc_now()

    agent = %Agent{
      id: agent_id,
      type: Keyword.get(config, :type, agent_module),
      state: Keyword.get(config, :initial_state, %{}),
      capabilities: Keyword.get(config, :capabilities, []),
      lifecycle: :initializing,
      version: 1,
      parent_id: Keyword.get(config, :parent_id),
      metadata: Map.merge(%{module: agent_module}, Keyword.get(config, :metadata, %{})),
      created_at: now,
      updated_at: now
    }

    # Start the agent process
    case start_agent_process(agent_module, agent, config) do
      {:ok, pid} ->
        # Register in registry
        case Registry.register(agent, pid) do
          :ok ->
            # Get the current agent from the server (which should have the initialized state)
            {:ok, current_agent} = Mabeam.Foundation.Agent.Server.get_agent(pid)

            # Update lifecycle state on the current (initialized) agent
            updated_agent = %{current_agent | lifecycle: :ready, updated_at: DateTime.utc_now()}
            Registry.update_agent(agent_id, fn _old -> updated_agent end)

            # Update the agent server's state as well  
            Mabeam.Foundation.Agent.Server.update_agent(pid, fn _old -> updated_agent end)

            # Emit lifecycle event
            emit_lifecycle_event(:started, updated_agent)

            {:ok, updated_agent, pid}

          {:error, reason} ->
            # Failed to register, stop the process
            if Process.alive?(pid) do
              Process.exit(pid, :kill)
            end

            emit_lifecycle_event(:start_failed, agent, reason: reason)
            {:error, :registration_failed}
        end

      {:error, reason} ->
        emit_lifecycle_event(:start_failed, agent, reason: reason)
        {:error, reason}
    end
  end

  @doc """
  Stops an agent gracefully.

  ## Parameters

  - `agent_id`: The ID of the agent to stop
  - `reason`: The reason for stopping (defaults to `:normal`)

  ## Returns

  - `:ok` - Agent stopped successfully
  - `{:error, reason}` - Failed to stop agent
  """
  @spec stop_agent(binary(), term()) :: :ok | {:error, term()}
  def stop_agent(agent_id, reason \\ :normal) when is_binary(agent_id) do
    with {:ok, agent} <- Registry.get_agent(agent_id),
         {:ok, pid} <- Registry.get_process(agent_id) do
      # Update lifecycle state
      updated_agent = %{agent | lifecycle: :terminating, updated_at: DateTime.utc_now()}
      Registry.update_agent(agent_id, fn _old -> updated_agent end)

      # Emit stopping event
      emit_lifecycle_event(:stopping, updated_agent, reason: reason)

      # Stop the process
      stop_agent_process(pid, reason)

      # Unregister from registry
      Registry.unregister(agent_id)

      # Emit stopped event
      emit_lifecycle_event(:stopped, updated_agent, reason: reason)
      :ok
    else
      {:error, :not_found} ->
        # Agent not found, consider it already stopped
        :ok
    end
  end

  @doc """
  Restarts an agent.

  ## Parameters

  - `agent_id`: The ID of the agent to restart
  - `config`: Optional configuration overrides

  ## Returns

  - `{:ok, agent, pid}` - Agent restarted successfully
  - `{:error, reason}` - Failed to restart agent
  """
  @spec restart_agent(binary(), agent_config()) :: lifecycle_result()
  def restart_agent(agent_id, config \\ []) when is_binary(agent_id) do
    with {:ok, agent} <- Registry.get_agent(agent_id) do
      # Stop the agent first - stop_agent only returns :ok currently
      :ok = stop_agent(agent_id, :restart)

      # Prepare restart configuration
      restart_config =
        config
        |> Keyword.put_new(:id, agent_id)
        |> Keyword.put_new(:type, agent.type)
        |> Keyword.put_new(:capabilities, agent.capabilities)
        |> Keyword.put_new(:metadata, agent.metadata)
        |> Keyword.put_new(:initial_state, agent.state)

      # Get the module from metadata
      agent_module = agent.metadata[:module]

      # Start the agent again
      start_agent(agent_module, restart_config)
    else
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Updates an agent's lifecycle state.

  ## Parameters

  - `agent_id`: The ID of the agent to update
  - `new_state`: The new lifecycle state

  ## Returns

  - `{:ok, agent}` - Agent updated successfully
  - `{:error, reason}` - Failed to update agent
  """
  @spec update_lifecycle_state(binary(), AgentTypes.lifecycle_state()) ::
          {:ok, Agent.t()} | {:error, term()}
  def update_lifecycle_state(agent_id, new_state) when is_binary(agent_id) do
    Registry.update_agent(agent_id, fn agent ->
      %{agent | lifecycle: new_state, updated_at: DateTime.utc_now()}
    end)
  end

  @doc """
  Gets the current lifecycle state of an agent.

  ## Parameters

  - `agent_id`: The ID of the agent to check

  ## Returns

  - `{:ok, lifecycle_state}` - Current lifecycle state
  - `{:error, :not_found}` - Agent not found
  """
  @spec get_lifecycle_state(binary()) ::
          {:ok, AgentTypes.lifecycle_state()} | {:error, :not_found}
  def get_lifecycle_state(agent_id) when is_binary(agent_id) do
    case Registry.get_agent(agent_id) do
      {:ok, agent} -> {:ok, agent.lifecycle}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  ## Private Functions

  defp start_agent_process(agent_module, agent, config) do
    # Default to a simple GenServer-based agent
    case Code.ensure_loaded(agent_module) do
      {:module, _} ->
        if function_exported?(agent_module, :start_link, 2) do
          agent_module.start_link(agent, config)
        else
          # Use default agent server
          Mabeam.Foundation.Agent.Server.start_link(agent, config)
        end

      {:error, reason} ->
        {:error, {:module_not_found, reason}}
    end
  end

  defp stop_agent_process(pid, reason) do
    if Process.alive?(pid) do
      # Use the provided reason for termination
      exit_reason = reason
      
      Process.exit(pid, exit_reason)
      :ok
    else
      :ok
    end
  end

  defp emit_lifecycle_event(event_type, agent, metadata \\ %{}) do
    # Convert keyword list to map if needed
    metadata = if is_list(metadata), do: Enum.into(metadata, %{}), else: metadata

    event_data = %{
      agent_id: agent.id,
      agent_type: agent.type,
      lifecycle_state: agent.lifecycle
    }

    full_metadata =
      Map.merge(metadata, %{
        agent_id: agent.id,
        agent_type: agent.type,
        lifecycle_state: agent.lifecycle
      })

    EventBus.emit("agent_lifecycle.#{event_type}", event_data, full_metadata)

    # Also emit telemetry
    :telemetry.execute(
      [:mabeam, :agent, :lifecycle],
      %{count: 1},
      Map.put(full_metadata, :event_type, event_type)
    )
  end
end
