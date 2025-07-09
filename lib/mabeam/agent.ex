defmodule Mabeam.Agent do
  @moduledoc """
  Agent behavior and API for the Mabeam system.
  
  This module provides the core agent abstraction with proper type safety,
  UUID-based IDs, and clean separation between agent data and processes.
  
  ## Key Strengths
  
  - **Type Safety**: Strong typing with TypedStruct and proper specs
  - **UUID-based IDs**: No more concatenated string IDs
  - **Clean Separation**: Agent data separate from process state
  - **Proper OTP**: Full OTP compliance with supervision trees
  - **Communication**: Events, signals, and messages for coordination
  - **Observability**: Built-in telemetry and metrics
  
  ## Usage
  
      # Define an agent behavior
      defmodule MyAgent do
        use Mabeam.Agent
        
        @impl true
        def init(agent, _config) do
          # Initialize agent-specific state
          {:ok, %{agent | state: %{counter: 0}}}
        end
        
        @impl true
        def handle_action(agent, :increment, _params) do
          new_state = %{agent.state | counter: agent.state.counter + 1}
          {:ok, %{agent | state: new_state}, %{result: :incremented}}
        end
        
        @impl true
        def handle_action(agent, :get_count, _params) do
          {:ok, agent, %{count: agent.state.counter}}
        end
      end
      
      # Start an agent
      {:ok, agent, pid} = MyAgent.start_link(
        type: :counter,
        capabilities: [:increment, :get_count],
        initial_state: %{counter: 0}
      )
      
      # Execute actions
      {:ok, result} = MyAgent.execute_action(pid, :increment, %{})
      {:ok, %{count: 1}} = MyAgent.execute_action(pid, :get_count, %{})
  """
  
  alias Mabeam.Types.Agent.Agent
  alias Mabeam.Types.ID
  alias Mabeam.Foundation.Agent.Lifecycle
  
  @type agent_result :: {:ok, Agent.t()} | {:error, term()}
  @type action_result :: {:ok, Agent.t(), term()} | {:error, term()}
  
  @doc """
  Initializes the agent with the given configuration.
  
  This callback is called when the agent is first created and should
  return the initialized agent with any necessary setup.
  """
  @callback init(Agent.t(), keyword()) :: agent_result()
  
  @doc """
  Handles an action request.
  
  This callback is called when an action is executed on the agent.
  It should return the updated agent and any result data.
  """
  @callback handle_action(Agent.t(), atom(), map()) :: action_result()
  
  @doc """
  Handles a signal from another agent or the system.
  
  This callback is called when a signal is received by the agent.
  It should return the updated agent.
  """
  @callback handle_signal(Agent.t(), Mabeam.Types.Communication.Signal.t()) :: agent_result()
  
  @doc """
  Handles an event from the event bus.
  
  This callback is called when an event is received by the agent.
  It should return the updated agent.
  """
  @callback handle_event(Agent.t(), Mabeam.Types.Communication.Event.t()) :: agent_result()
  
  @doc """
  Handles termination of the agent.
  
  This callback is called when the agent is being terminated.
  It should perform any necessary cleanup.
  """
  @callback terminate(Agent.t(), term()) :: :ok
  
  @optional_callbacks [
    init: 2,
    handle_action: 3,
    handle_signal: 2,
    handle_event: 2,
    terminate: 2
  ]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Mabeam.Agent
      
      alias Mabeam.Types.Agent.Agent
      alias Mabeam.Types.ID
      alias Mabeam.Foundation.Agent.Lifecycle
      
      @doc """
      Starts an agent with the given configuration.
      
      ## Options
      
      - `:id` - Custom agent ID (defaults to generated UUID)
      - `:type` - Agent type (defaults to module name)
      - `:capabilities` - List of capabilities (defaults to empty list)
      - `:metadata` - Additional metadata (defaults to empty map)
      - `:initial_state` - Initial state for the agent (defaults to empty map)
      """
      @spec start_link(keyword()) :: {:ok, Agent.t(), pid()} | {:error, term()}
      def start_link(config \\ []) do
        # Only set type to module if not provided by user
        config = Keyword.put_new(config, :type, __MODULE__)
        Lifecycle.start_agent(__MODULE__, config)
      end
      
      @doc """
      Executes an action on the agent.
      
      ## Parameters
      
      - `server` - The agent process (PID or registered name)
      - `action` - The action to execute
      - `params` - Parameters for the action
      """
      @spec execute_action(GenServer.server(), atom(), map()) :: {:ok, term()} | {:error, term()}
      def execute_action(server, action, params \\ %{}) do
        Mabeam.Foundation.Agent.Server.execute_action(server, action, params)
      end
      
      @doc """
      Gets the current agent data.
      
      ## Parameters
      
      - `server` - The agent process (PID or registered name)
      """
      @spec get_agent(GenServer.server()) :: {:ok, Agent.t()} | {:error, term()}
      def get_agent(server) do
        Mabeam.Foundation.Agent.Server.get_agent(server)
      end
      
      @doc """
      Updates the agent data.
      
      ## Parameters
      
      - `server` - The agent process (PID or registered name)
      - `update_fn` - Function to update the agent
      """
      @spec update_agent(GenServer.server(), (Agent.t() -> Agent.t())) :: {:ok, Agent.t()} | {:error, term()}
      def update_agent(server, update_fn) do
        Mabeam.Foundation.Agent.Server.update_agent(server, update_fn)
      end
      
      # Default implementations
      
      @impl Mabeam.Agent
      def init(agent, _config) do
        {:ok, agent}
      end
      
      @impl Mabeam.Agent
      def handle_action(agent, action, params) do
        {:error, {:unknown_action, action}}
      end
      
      @impl Mabeam.Agent
      def handle_signal(agent, signal) do
        {:ok, agent}
      end
      
      @impl Mabeam.Agent
      def handle_event(agent, event) do
        {:ok, agent}
      end
      
      @impl Mabeam.Agent
      def terminate(agent, reason) do
        :ok
      end
      
      defoverridable [
        init: 2,
        handle_action: 3,
        handle_signal: 2,
        handle_event: 2,
        terminate: 2
      ]
    end
  end
  
  @doc """
  Creates a new agent with the given configuration.
  
  ## Options
  
  - `:id` - Custom agent ID (defaults to generated UUID)
  - `:type` - Agent type (required)
  - `:capabilities` - List of capabilities (defaults to empty list)
  - `:metadata` - Additional metadata (defaults to empty map)
  - `:initial_state` - Initial state for the agent (defaults to empty map)
  """
  @spec new(keyword()) :: Agent.t()
  def new(opts \\ []) do
    # Generate or use provided ID
    agent_id = case Keyword.get(opts, :id) do
      nil -> ID.agent_id() |> ID.unwrap()
      custom_id when is_binary(custom_id) -> custom_id
      other -> "#{other}"
    end
    
    now = DateTime.utc_now()
    
    %Agent{
      id: agent_id,
      type: Keyword.fetch!(opts, :type),
      state: Keyword.get(opts, :initial_state, %{}),
      capabilities: Keyword.get(opts, :capabilities, []),
      lifecycle: :initializing,
      version: 1,
      parent_id: Keyword.get(opts, :parent_id),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: now,
      updated_at: now
    }
  end
  
  @doc """
  Starts an agent with the given module and configuration.
  
  This is a convenience function for starting agents without
  having to call the module's start_link function directly.
  """
  @spec start_agent(module(), keyword()) :: {:ok, Agent.t(), pid()} | {:error, term()}
  def start_agent(agent_module, config \\ []) do
    Lifecycle.start_agent(agent_module, config)
  end
  
  @doc """
  Stops an agent gracefully.
  
  ## Parameters
  
  - `agent_id` - The ID of the agent to stop
  - `reason` - The reason for stopping (defaults to `:normal`)
  """
  @spec stop_agent(binary(), term()) :: :ok | {:error, term()}
  def stop_agent(agent_id, reason \\ :normal) do
    Lifecycle.stop_agent(agent_id, reason)
  end
  
  @doc """
  Restarts an agent.
  
  ## Parameters
  
  - `agent_id` - The ID of the agent to restart
  - `config` - Optional configuration overrides
  """
  @spec restart_agent(binary(), keyword()) :: {:ok, Agent.t(), pid()} | {:error, term()}
  def restart_agent(agent_id, config \\ []) do
    Lifecycle.restart_agent(agent_id, config)
  end
  
  @doc """
  Lists all agents of a specific type.
  
  ## Parameters
  
  - `type` - The agent type to filter by
  """
  @spec list_agents_by_type(atom()) :: [Agent.t()]
  def list_agents_by_type(type) do
    Mabeam.Foundation.Registry.find_by_type(type)
  end
  
  @doc """
  Lists all agents with a specific capability.
  
  ## Parameters
  
  - `capability` - The capability to filter by
  """
  @spec list_agents_by_capability(atom()) :: [Agent.t()]
  def list_agents_by_capability(capability) do
    Mabeam.Foundation.Registry.find_by_capability(capability)
  end
  
  @doc """
  Gets an agent by ID.
  
  ## Parameters
  
  - `agent_id` - The ID of the agent to retrieve
  """
  @spec get_agent_by_id(binary()) :: {:ok, Agent.t()} | {:error, :not_found}
  def get_agent_by_id(agent_id) do
    Mabeam.Foundation.Registry.get_agent(agent_id)
  end
  
  @doc """
  Gets an agent process by ID.
  
  ## Parameters
  
  - `agent_id` - The ID of the agent to retrieve
  """
  @spec get_agent_process(binary()) :: {:ok, pid()} | {:error, :not_found}
  def get_agent_process(agent_id) do
    Mabeam.Foundation.Registry.get_process(agent_id)
  end
end
