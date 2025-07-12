defmodule Mabeam.Foundation.Agent.Server do
  @moduledoc """
  Generic agent server implementation.

  This module provides a basic GenServer-based agent server that can be used
  as a default implementation for agents that don't provide their own server.
  """

  use GenServer
  require Logger
  alias Mabeam.Debug

  alias Mabeam.Types.Agent.Agent
  alias Mabeam.Types.Communication.{Signal, Message}
  alias Mabeam.Foundation.Communication.EventBus

  @type server_state :: %{
          agent: Agent.t(),
          config: keyword(),
          message_queue: :queue.queue(Message.t()),
          processing: boolean()
        }

  ## Client API

  @spec start_link(Agent.t(), keyword()) :: GenServer.on_start()
  def start_link(agent, config \\ []) do
    GenServer.start_link(__MODULE__, {agent, config})
  end

  @spec get_agent(GenServer.server()) :: {:ok, Agent.t()} | {:error, term()}
  def get_agent(server) do
    GenServer.call(server, :get_agent)
  end

  @spec update_agent(GenServer.server(), (Agent.t() -> Agent.t())) ::
          {:ok, Agent.t()} | {:error, term()}
  def update_agent(server, update_fn) when is_function(update_fn, 1) do
    GenServer.call(server, {:update_agent, update_fn})
  end

  @spec execute_action(GenServer.server(), atom(), map()) :: {:ok, term()} | {:error, term()}
  def execute_action(server, action, params \\ %{}) do
    GenServer.call(server, {:execute_action, action, params})
  end

  @spec send_message(GenServer.server(), Message.t()) :: :ok
  def send_message(server, message) do
    GenServer.cast(server, {:message, message})
  end

  @spec send_signal(GenServer.server(), Signal.t()) :: :ok
  def send_signal(server, signal) do
    GenServer.cast(server, {:signal, signal})
  end

  ## Server Implementation

  @impl GenServer
  def init({agent, config}) do
    # Subscribe to relevant events
    EventBus.subscribe_pattern("agent_lifecycle.*")

    # Initialize the agent if it has an agent module
    initialized_agent =
      case get_in(agent.metadata, [:module]) do
        nil ->
          agent

        agent_module when is_atom(agent_module) ->
          try do
            case agent_module.init(agent, config) do
              {:ok, updated_agent} ->
                updated_agent

              {:error, reason} ->
                Logger.error("Agent initialization failed",
                  agent_id: agent.id,
                  agent_module: agent_module,
                  reason: inspect(reason)
                )

                agent
            end
          rescue
            error ->
              Logger.error("Agent initialization crashed",
                agent_id: agent.id,
                agent_module: agent_module,
                error: inspect(error)
              )

              agent
          end
      end

    state = %{
      agent: initialized_agent,
      config: config,
      message_queue: :queue.new(),
      processing: false
    }

    Logger.info("Agent server started", agent_id: agent.id, agent_type: agent.type)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_agent, _from, state) do
    {:reply, {:ok, state.agent}, state}
  end

  @impl GenServer
  def handle_call({:update_agent, update_fn}, _from, state) do
    try do
      updated_agent = update_fn.(state.agent)
      new_state = %{state | agent: updated_agent}
      {:reply, {:ok, updated_agent}, new_state}
    rescue
      error ->
        {:reply, {:error, error}, state}
    end
  end

  @impl GenServer
  def handle_call({:execute_action, action, params}, _from, state) do
    # Get the agent module from metadata
    agent_module = get_in(state.agent.metadata, [:module])

    if agent_module && Code.ensure_loaded?(agent_module) do
      # Call the agent's handle_action callback directly to get updated agent
      try do
        case agent_module.handle_action(state.agent, action, params) do
          {:ok, updated_agent, result} ->
            # Update the server state with the new agent state
            new_state = %{state | agent: updated_agent}

            # Emit action executed event
            EventBus.emit("action_executed", %{
              agent_id: state.agent.id,
              action: action,
              params: params,
              result: result
            })

            {:reply, {:ok, result}, new_state}

          {:error, reason} ->
            # Emit action failed event
            EventBus.emit("action_failed", %{
              agent_id: state.agent.id,
              action: action,
              params: params,
              reason: reason
            })

            {:reply, {:error, reason}, state}

          other ->
            Logger.warning("Agent action returned unexpected format",
              agent_id: state.agent.id,
              action: action,
              result: inspect(other)
            )

            {:reply, {:error, {:invalid_response, other}}, state}
        end
      rescue
        error ->
          Logger.error("Agent action execution failed",
            agent_id: state.agent.id,
            action: action,
            error: inspect(error)
          )

          {:reply, {:error, {:execution_failed, error}}, state}
      end
    else
      # Fallback to default action execution
      case execute_agent_action(state.agent, action, params) do
        {:ok, result} ->
          # Update agent state if needed
          updated_agent = %{
            state.agent
            | state: Map.put(state.agent.state, :last_action, action),
              updated_at: DateTime.utc_now()
          }

          new_state = %{state | agent: updated_agent}

          # Emit action executed event
          EventBus.emit("action_executed", %{
            agent_id: state.agent.id,
            action: action,
            params: params,
            result: result
          })

          {:reply, {:ok, result}, new_state}

        {:error, reason} ->
          # Emit action failed event
          EventBus.emit("action_failed", %{
            agent_id: state.agent.id,
            action: action,
            params: params,
            reason: reason
          })

          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl GenServer
  def handle_cast({:message, message}, state) do
    # Queue the message for processing
    new_queue = :queue.in(message, state.message_queue)
    new_state = %{state | message_queue: new_queue}

    # Process messages if not already processing
    final_state =
      if not state.processing do
        send(self(), :process_messages)
        %{new_state | processing: true}
      else
        new_state
      end

    {:noreply, final_state}
  end

  @impl GenServer
  def handle_cast({:signal, signal}, state) do
    # Handle signal immediately
    handle_agent_signal(state.agent, signal)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:process_messages, state) do
    case :queue.out(state.message_queue) do
      {{:value, message}, remaining_queue} ->
        # Process the message
        handle_agent_message(state.agent, message)

        # Continue processing if there are more messages
        if :queue.is_empty(remaining_queue) do
          new_state = %{state | message_queue: remaining_queue, processing: false}
          {:noreply, new_state}
        else
          send(self(), :process_messages)
          new_state = %{state | message_queue: remaining_queue}
          {:noreply, new_state}
        end

      {:empty, _} ->
        # No more messages to process
        new_state = %{state | processing: false}
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info({:event, event}, state) do
    # Handle events from the event bus and update state if agent is updated
    Debug.log("Agent server handling event",
      agent_id: state.agent.id,
      event_type: event.type
    )

    case handle_agent_event(state.agent, event) do
      {:ok, updated_agent} ->
        Debug.log("Agent server updated agent state",
          agent_id: state.agent.id,
          event_type: event.type,
          state_changed: state.agent.state != updated_agent.state
        )

        new_state = %{state | agent: updated_agent}
        {:noreply, new_state}

      :ok ->
        Debug.log("Agent server event handled without state change",
          agent_id: state.agent.id,
          event_type: event.type
        )

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Agent event handling failed",
          agent_id: state.agent.id,
          event_type: event.type,
          reason: inspect(reason)
        )

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("Unhandled message in agent server",
      agent_id: state.agent.id,
      message: inspect(msg)
    )

    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Agent server terminating",
      agent_id: state.agent.id,
      reason: inspect(reason)
    )

    # Skip termination event during testing to avoid EventBus congestion
    unless Mix.env() == :test do
      Task.start(fn ->
        EventBus.emit("agent_terminated", %{
          agent_id: state.agent.id,
          reason: reason
        })
      end)
    end

    :ok
  end

  ## Private Functions

  defp execute_agent_action(agent, action, params) do
    # Get the agent module from metadata
    agent_module = get_in(agent.metadata, [:module])

    if agent_module && Code.ensure_loaded?(agent_module) do
      # Call the agent's handle_action callback
      try do
        case agent_module.handle_action(agent, action, params) do
          {:ok, _updated_agent, result} ->
            # Update the agent state and return the result
            # Note: The caller will handle updating the server state
            {:ok, result}

          {:error, reason} ->
            {:error, reason}

          other ->
            Logger.warning("Agent action returned unexpected format",
              agent_id: agent.id,
              action: action,
              result: inspect(other)
            )

            {:error, {:invalid_response, other}}
        end
      rescue
        error ->
          Logger.error("Agent action execution failed",
            agent_id: agent.id,
            action: action,
            error: inspect(error)
          )

          {:error, {:execution_failed, error}}
      end
    else
      # Fallback to default actions if no agent module is available
      case action do
        :ping ->
          {:ok, %{agent_id: agent.id, timestamp: DateTime.utc_now(), params: params}}

        :get_state ->
          {:ok, agent.state}

        :get_capabilities ->
          {:ok, agent.capabilities}

        :get_metadata ->
          {:ok, agent.metadata}

        unknown_action ->
          {:error, {:unknown_action, unknown_action}}
      end
    end
  end

  defp handle_agent_message(agent, message) do
    Debug.log("Agent received message",
      agent_id: agent.id,
      message_type: message.type,
      message_id: message.id
    )

    # Default message handling - can be extended
    case message.type do
      :ping ->
        if message.reply_to do
          # Send pong response
          response = %Message{
            id: UUID.uuid4(),
            type: :pong,
            source: agent.id,
            target: message.reply_to,
            data: %{original_message_id: message.id},
            correlation_id: message.correlation_id,
            timestamp: DateTime.utc_now()
          }

          # Send response (this would typically go through a message router)
          Debug.log("Agent sending pong response",
            agent_id: agent.id,
            response_id: response.id
          )
        end

      _ ->
        Logger.info("Agent received unhandled message",
          agent_id: agent.id,
          message_type: message.type
        )
    end
  end

  defp handle_agent_signal(agent, signal) do
    Debug.log("Agent received signal",
      agent_id: agent.id,
      signal_type: signal.type,
      signal_id: signal.id
    )

    # Default signal handling - can be extended
    case signal.type do
      :status_check ->
        # Emit status response
        EventBus.emit("agent_status", %{
          agent_id: agent.id,
          status: :active,
          timestamp: DateTime.utc_now()
        })

      _ ->
        Logger.info("Agent received unhandled signal",
          agent_id: agent.id,
          signal_type: signal.type
        )
    end
  end

  defp handle_agent_event(agent, event) do
    Debug.log("Agent received event",
      agent_id: agent.id,
      event_type: event.type,
      event_id: event.id
    )

    # Process event normally

    # Get the agent module from metadata
    agent_module = get_in(agent.metadata, [:module])

    result =
      if agent_module && Code.ensure_loaded?(agent_module) &&
           function_exported?(agent_module, :handle_event, 2) do
        # Call the agent's handle_event callback
        try do
          case agent_module.handle_event(agent, event) do
            {:ok, updated_agent} ->
              Debug.log("Agent event handling succeeded",
                agent_id: agent.id,
                event_type: event.type,
                state_changed: agent.state != updated_agent.state
              )

              # Return the updated agent to update server state
              {:ok, updated_agent}

            {:error, reason} ->
              Logger.warning("Agent event handling failed",
                agent_id: agent.id,
                event_type: event.type,
                reason: inspect(reason)
              )

              {:error, reason}
          end
        rescue
          error ->
            Logger.error("Agent event handling crashed",
              agent_id: agent.id,
              event_type: event.type,
              error: inspect(error),
              stacktrace: Exception.format_stacktrace(__STACKTRACE__)
            )

            {:error, {:crash, error}}
        end
      else
        # No agent module or handle_event function
        :ok
      end

    # Default event handling - can be extended
    case event.type do
      :system_shutdown ->
        # Graceful shutdown
        Process.exit(self(), :shutdown)

      _ ->
        Debug.log("Agent received unhandled event",
          agent_id: agent.id,
          event_type: event.type
        )
    end

    # Return result from agent module
    result
  end
end
