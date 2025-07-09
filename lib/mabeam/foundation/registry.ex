defmodule Mabeam.Foundation.Registry do
  @moduledoc """
  Type-safe registry for agent management.

  This module provides a centralized registry for all agents in the system,
  with type-safe lookups and automatic cleanup of dead processes.
  """

  use GenServer
  require Logger

  alias Mabeam.Types.Agent.Agent

  @type agent_id :: String.t()
  @type agent_ref :: pid() | atom() | {name :: atom(), node :: node()}

  @type registration :: %{
          agent_id: agent_id(),
          agent_ref: agent_ref(),
          agent_data: Agent.t(),
          node: node(),
          metadata: map(),
          registered_at: DateTime.t(),
          last_seen: DateTime.t()
        }

  @type state :: %{
          registrations: %{agent_id() => registration()},
          indices: %{
            by_type: %{atom() => MapSet.t(agent_id())},
            by_capability: %{atom() => MapSet.t(agent_id())},
            by_node: %{node() => MapSet.t(agent_id())}
          },
          monitors: %{reference() => agent_id()}
        }

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register(Agent.t(), pid()) :: :ok | {:error, term()}
  def register(%Agent{} = agent, process) when is_pid(process) do
    GenServer.call(__MODULE__, {:register, agent.id, agent, process})
  end

  @spec get_agent(agent_id()) :: {:ok, Agent.t()} | {:error, :not_found}
  def get_agent(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:get_agent, agent_id})
  end

  @spec get_process(agent_id()) :: {:ok, pid()} | {:error, :not_found}
  def get_process(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:get_process, agent_id})
  end

  @spec update_agent(agent_id(), (Agent.t() -> Agent.t())) :: {:ok, Agent.t()} | {:error, term()}
  def update_agent(agent_id, update_fn) when is_binary(agent_id) and is_function(update_fn, 1) do
    GenServer.call(__MODULE__, {:update_agent, agent_id, update_fn})
  end

  @spec find_by_type(atom()) :: [Agent.t()]
  def find_by_type(type) when is_atom(type) do
    GenServer.call(__MODULE__, {:find_by_type, type})
  end

  @spec find_by_capability(atom()) :: [Agent.t()]
  def find_by_capability(capability) when is_atom(capability) do
    GenServer.call(__MODULE__, {:find_by_capability, capability})
  end

  @spec list_all() :: [Agent.t()]
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @spec unregister(agent_id()) :: :ok
  def unregister(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:unregister, agent_id})
  end

  ## Server Implementation

  @impl GenServer
  def init(_opts) do
    state = %{
      registrations: %{},
      indices: %{
        by_type: %{},
        by_capability: %{},
        by_node: %{}
      },
      monitors: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register, agent_id, agent, process}, _from, state) do
    case Map.get(state.registrations, agent_id) do
      nil ->
        # Monitor the process
        ref = Process.monitor(process)

        # Create registration
        registration = %{
          agent_id: agent_id,
          agent_ref: process,
          agent_data: agent,
          node: node(process),
          metadata: %{},
          registered_at: DateTime.utc_now(),
          last_seen: DateTime.utc_now()
        }

        # Update state
        new_state =
          state
          |> put_in([:registrations, agent_id], registration)
          |> put_in([:monitors, ref], agent_id)
          |> update_indices(:add, agent)

        # Emit telemetry
        :telemetry.execute(
          [:mabeam, :registry, :register],
          %{count: 1},
          %{agent_id: agent_id, agent_type: agent.type}
        )

        {:reply, :ok, new_state}

      _existing ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_agent, agent_id}, _from, state) do
    case Map.get(state.registrations, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      registration ->
        {:reply, {:ok, registration.agent_data}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_process, agent_id}, _from, state) do
    case Map.get(state.registrations, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      registration ->
        {:reply, {:ok, registration.agent_ref}, state}
    end
  end

  @impl GenServer
  def handle_call({:update_agent, agent_id, update_fn}, _from, state) do
    case Map.get(state.registrations, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      registration ->
        try do
          updated_agent = update_fn.(registration.agent_data)
          updated_registration = %{registration | agent_data: updated_agent}

          new_state = put_in(state, [:registrations, agent_id], updated_registration)

          {:reply, {:ok, updated_agent}, new_state}
        rescue
          error ->
            {:reply, {:error, error}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:find_by_type, type}, _from, state) do
    agent_ids = get_in(state, [:indices, :by_type, type]) || MapSet.new()

    agents =
      agent_ids
      |> MapSet.to_list()
      |> Enum.map(&get_in(state, [:registrations, &1, :agent_data]))
      |> Enum.filter(& &1)

    {:reply, agents, state}
  end

  @impl GenServer
  def handle_call({:find_by_capability, capability}, _from, state) do
    agent_ids = get_in(state, [:indices, :by_capability, capability]) || MapSet.new()

    agents =
      agent_ids
      |> MapSet.to_list()
      |> Enum.map(&get_in(state, [:registrations, &1, :agent_data]))
      |> Enum.filter(& &1)

    {:reply, agents, state}
  end

  @impl GenServer
  def handle_call(:list_all, _from, state) do
    agents =
      state.registrations
      |> Enum.map(fn {_id, registration} -> registration.agent_data end)

    {:reply, agents, state}
  end

  @impl GenServer
  def handle_call({:unregister, agent_id}, _from, state) do
    case Map.get(state.registrations, agent_id) do
      nil ->
        {:reply, :ok, state}

      registration ->
        # Find and remove monitor
        monitor_ref =
          Enum.find_value(state.monitors, fn {ref, id} ->
            if id == agent_id, do: ref
          end)

        if monitor_ref do
          Process.demonitor(monitor_ref, [:flush])
        end

        # Clean up
        new_state =
          state
          |> update_in([:registrations], &Map.delete(&1, agent_id))
          |> update_in([:monitors], &Map.delete(&1, monitor_ref))
          |> update_indices(:remove, registration.agent_data)

        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      agent_id ->
        Logger.info("Agent #{agent_id} process down: #{inspect(reason)}")

        # Get agent data before removal
        registration = get_in(state, [:registrations, agent_id])

        # Clean up
        new_state =
          state
          |> update_in([:registrations], &Map.delete(&1, agent_id))
          |> update_in([:monitors], &Map.delete(&1, ref))
          |> update_indices(:remove, registration.agent_data)

        # Emit telemetry
        :telemetry.execute(
          [:mabeam, :registry, :unregister],
          %{count: 1},
          %{agent_id: agent_id, reason: reason}
        )

        {:noreply, new_state}
    end
  end

  ## Private Functions

  defp update_indices(state, :add, agent) do
    state
    |> update_in([:indices, :by_type, agent.type], &MapSet.put(&1 || MapSet.new(), agent.id))
    |> update_agent_capabilities(agent, :add)
    |> update_in([:indices, :by_node, node()], &MapSet.put(&1 || MapSet.new(), agent.id))
  end

  defp update_indices(state, :remove, agent) do
    state
    |> update_in([:indices, :by_type, agent.type], &MapSet.delete(&1 || MapSet.new(), agent.id))
    |> update_agent_capabilities(agent, :remove)
    |> update_in([:indices, :by_node, node()], &MapSet.delete(&1 || MapSet.new(), agent.id))
  end

  defp update_agent_capabilities(state, agent, operation) do
    Enum.reduce(agent.capabilities, state, fn capability, acc ->
      case operation do
        :add ->
          update_in(
            acc,
            [:indices, :by_capability, capability],
            &MapSet.put(&1 || MapSet.new(), agent.id)
          )

        :remove ->
          update_in(
            acc,
            [:indices, :by_capability, capability],
            &MapSet.delete(&1 || MapSet.new(), agent.id)
          )
      end
    end)
  end
end
