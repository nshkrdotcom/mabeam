defmodule Mabeam do
  @moduledoc """
  Mabeam - A unified agent system for Elixir.

  This module provides the main API for the Mabeam system.

  ## Key Improvements

  - **Type Safety**: Strong typing with proper specs and TypedStruct
  - **UUID-based IDs**: No more concatenated string IDs
  - **Clean Architecture**: Proper separation of concerns
  - **OTP Compliance**: Full OTP supervision trees
  - **Communication**: Events, signals, and messages
  - **Observability**: Built-in telemetry and metrics
  - **Foundation Layer**: Robust infrastructure services

  ## Usage

  ### Starting the System

  The system starts automatically when the application starts. You can also
  start it manually:

      {:ok, _pid} = Mabeam.start()

  ### Creating Agents

      defmodule MyAgent do
        use Mabeam.Agent
        
        @impl true
        def handle_action(agent, :ping, _params) do
          {:ok, agent, %{response: :pong, timestamp: DateTime.utc_now()}}
        end
      end
      
      # Start an agent
      {:ok, agent, pid} = MyAgent.start_link(
        type: :demo,
        capabilities: [:ping]
      )
      
      # Execute actions
      {:ok, result} = MyAgent.execute_action(pid, :ping, %{})

  ### Agent Management

      # List all agents
      agents = Mabeam.list_agents()
      
      # Find agents by type
      demo_agents = Mabeam.list_agents_by_type(:demo)
      
      # Find agents by capability
      ping_agents = Mabeam.list_agents_by_capability(:ping)
      
      # Get agent by ID
      {:ok, agent} = Mabeam.get_agent("agent_uuid")
      
      # Stop an agent
      :ok = Mabeam.stop_agent("agent_uuid")

  ### Communication

      # Subscribe to events
      Mabeam.subscribe(:agent_lifecycle)
      
      # Emit events
      Mabeam.emit_event(:custom_event, %{data: "value"})
  """

  alias Mabeam.Agent
  alias Mabeam.Foundation.Registry
  alias Mabeam.Foundation.Communication.EventBus

  @doc """
  Starts the Mabeam system.

  This is typically not needed as the system starts automatically
  with the application.
  """
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    Mabeam.Application.start(:normal, [])
  end

  @doc """
  Lists all agents in the system.
  """
  @spec list_agents() :: [Mabeam.Types.Agent.t()]
  def list_agents do
    Registry.list_all()
  end

  @doc """
  Lists agents by type.

  ## Parameters

  - `type` - The agent type to filter by
  """
  @spec list_agents_by_type(atom()) :: [Mabeam.Types.Agent.t()]
  def list_agents_by_type(type) do
    Agent.list_agents_by_type(type)
  end

  @doc """
  Lists agents by capability.

  ## Parameters

  - `capability` - The capability to filter by
  """
  @spec list_agents_by_capability(atom()) :: [Mabeam.Types.Agent.t()]
  def list_agents_by_capability(capability) do
    Agent.list_agents_by_capability(capability)
  end

  @doc """
  Gets an agent by ID.

  ## Parameters

  - `agent_id` - The ID of the agent to retrieve
  """
  @spec get_agent(binary()) :: {:ok, Mabeam.Types.Agent.t()} | {:error, :not_found}
  def get_agent(agent_id) do
    Agent.get_agent_by_id(agent_id)
  end

  @doc """
  Gets an agent process by ID.

  ## Parameters

  - `agent_id` - The ID of the agent to retrieve
  """
  @spec get_agent_process(binary()) :: {:ok, pid()} | {:error, :not_found}
  def get_agent_process(agent_id) do
    Agent.get_agent_process(agent_id)
  end

  @doc """
  Starts an agent with the given module and configuration.

  ## Parameters

  - `agent_module` - The module implementing the agent behavior
  - `config` - Configuration options for the agent
  """
  @spec start_agent(module(), keyword()) ::
          {:ok, Mabeam.Types.Agent.t(), pid()} | {:error, term()}
  def start_agent(agent_module, config \\ []) do
    Agent.start_agent(agent_module, config)
  end

  @doc """
  Stops an agent gracefully.

  ## Parameters

  - `agent_id` - The ID of the agent to stop
  - `reason` - The reason for stopping (defaults to `:normal`)
  """
  @spec stop_agent(binary(), term()) :: :ok | {:error, term()}
  def stop_agent(agent_id, reason \\ :normal) do
    Agent.stop_agent(agent_id, reason)
  end

  @doc """
  Restarts an agent.

  ## Parameters

  - `agent_id` - The ID of the agent to restart
  - `config` - Optional configuration overrides
  """
  @spec restart_agent(binary(), keyword()) ::
          {:ok, Mabeam.Types.Agent.t(), pid()} | {:error, term()}
  def restart_agent(agent_id, config \\ []) do
    Agent.restart_agent(agent_id, config)
  end

  @doc """
  Subscribes to events from the event bus.

  ## Parameters

  - `event_type` - The type of events to subscribe to
  """
  @spec subscribe(atom()) :: :ok
  def subscribe(event_type) do
    EventBus.subscribe(event_type)
  end

  @doc """
  Subscribes to events matching a pattern.

  ## Parameters

  - `pattern` - The pattern to match events against
  """
  @spec subscribe_pattern(binary()) :: :ok
  def subscribe_pattern(pattern) do
    EventBus.subscribe_pattern(pattern)
  end

  @doc """
  Emits an event to the event bus.

  ## Parameters

  - `event_type` - The type of event to emit
  - `data` - The event data
  - `metadata` - Additional metadata (optional)
  """
  @spec emit_event(atom(), term(), map()) :: {:ok, String.t()}
  def emit_event(event_type, data, metadata \\ %{}) do
    EventBus.emit(event_type, data, metadata)
  end

  @doc """
  Gets the event history from the event bus.

  ## Parameters

  - `limit` - Maximum number of events to return (defaults to 100)
  """
  @spec get_event_history(pos_integer()) :: [Mabeam.Types.Communication.Event.t()]
  def get_event_history(limit \\ 100) do
    EventBus.get_history(limit)
  end
end
