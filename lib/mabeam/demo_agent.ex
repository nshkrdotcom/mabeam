defmodule Mabeam.DemoAgent do
  @moduledoc """
  A demonstration agent showing the capabilities of the Mabeam system.

  This agent demonstrates:
  - Type-safe UUID-based IDs
  - Action handling with proper return types
  - Event emission and handling
  - State management
  - Proper OTP supervision
  """

  use Mabeam.Agent
  require Logger

  @impl Mabeam.Agent
  def init(agent, config) do
    # Subscribe to some events
    Mabeam.subscribe(:system_status)
    Mabeam.subscribe_pattern("demo.*")

    # Initialize state - merge existing state with defaults
    default_state = %{
      counter: 0,
      messages: [],
      started_at: DateTime.utc_now(),
      config: config
    }

    # Only merge if agent.state has meaningful data (non-empty map)
    initial_state =
      if map_size(agent.state) > 0 do
        Map.merge(default_state, agent.state)
      else
        default_state
      end

    result_agent = %{agent | state: initial_state}

    {:ok, result_agent}
  end

  @impl Mabeam.Agent
  def handle_action(agent, :ping, _params) do
    # Emit a ping event
    {:ok, _event_id} =
      Mabeam.emit_event(:demo_ping, %{
        agent_id: agent.id,
        timestamp: DateTime.utc_now()
      })

    result = %{
      response: :pong,
      agent_id: agent.id,
      timestamp: DateTime.utc_now(),
      counter: agent.state.counter
    }

    {:ok, agent, result}
  end

  @impl Mabeam.Agent
  def handle_action(agent, :increment, %{"amount" => amount}) when is_integer(amount) do
    new_counter = agent.state.counter + amount
    new_state = %{agent.state | counter: new_counter}
    updated_agent = %{agent | state: new_state}

    # Emit increment event
    {:ok, _event_id} =
      Mabeam.emit_event(:demo_increment, %{
        agent_id: agent.id,
        old_value: agent.state.counter,
        new_value: new_counter,
        amount: amount
      })

    result = %{
      counter: new_counter,
      incremented_by: amount
    }

    {:ok, updated_agent, result}
  end

  @impl Mabeam.Agent
  def handle_action(agent, :increment, _params) do
    # Default increment by 1
    handle_action(agent, :increment, %{"amount" => 1})
  end

  @impl Mabeam.Agent
  def handle_action(agent, :get_state, _params) do
    result = %{
      state: agent.state,
      lifecycle: agent.lifecycle,
      capabilities: agent.capabilities,
      type: agent.type,
      created_at: agent.created_at,
      updated_at: agent.updated_at
    }

    {:ok, agent, result}
  end

  @impl Mabeam.Agent
  def handle_action(agent, :add_message, %{"message" => message}) when is_binary(message) do
    new_message = %{
      id: UUID.uuid4(),
      content: message,
      timestamp: DateTime.utc_now()
    }

    new_messages = [new_message | agent.state.messages]
    new_state = %{agent.state | messages: new_messages}
    updated_agent = %{agent | state: new_state}

    # Emit message added event
    {:ok, _event_id} =
      Mabeam.emit_event(:demo_message_added, %{
        agent_id: agent.id,
        message: new_message
      })

    result = %{
      message_id: new_message.id,
      total_messages: length(new_messages)
    }

    {:ok, updated_agent, result}
  end

  @impl Mabeam.Agent
  def handle_action(agent, :get_messages, _params) do
    result = %{
      messages: agent.state.messages,
      count: length(agent.state.messages)
    }

    {:ok, agent, result}
  end

  @impl Mabeam.Agent
  def handle_action(agent, :clear_messages, _params) do
    old_count = length(agent.state.messages)
    new_state = %{agent.state | messages: []}
    updated_agent = %{agent | state: new_state}

    # Emit messages cleared event
    {:ok, _event_id} =
      Mabeam.emit_event(:demo_messages_cleared, %{
        agent_id: agent.id,
        cleared_count: old_count
      })

    result = %{
      cleared_count: old_count
    }

    {:ok, updated_agent, result}
  end

  @impl Mabeam.Agent
  def handle_action(agent, :simulate_error, _params) do
    # Emit error event
    {:ok, _event_id} =
      Mabeam.emit_event(:demo_error, %{
        agent_id: agent.id,
        error_type: :simulated,
        timestamp: DateTime.utc_now()
      })

    {:error, :simulated_error}
  end

  @impl Mabeam.Agent
  def handle_action(agent, action, params) do
    Logger.debug("DemoAgent received unknown action",
      agent_id: agent.id,
      action: action,
      params: params
    )

    {:error, :unknown_action}
  end

  @impl Mabeam.Agent
  def handle_event(agent, event) do
    # Handle some events
    case event.type do
      :system_status ->
        # Respond to system status check
        {:ok, _event_id} =
          Mabeam.emit_event(:demo_status_response, %{
            agent_id: agent.id,
            status: :healthy,
            counter: Map.get(agent.state, :counter, 0),
            message_count: length(Map.get(agent.state, :messages, []))
          })

        # Event emitted successfully

        {:ok, agent}

      _ ->
        # Ignore other events

        {:ok, agent}
    end
  end

  @impl Mabeam.Agent
  def handle_signal(agent, _signal) do
    # For now, just log signals
    {:ok, agent}
  end

  @impl Mabeam.Agent
  def terminate(agent, reason) do
    Logger.info("DemoAgent terminating",
      agent_id: agent.id,
      reason: reason
    )

    # Emit termination event
    {:ok, _event_id} =
      Mabeam.emit_event(:demo_terminated, %{
        agent_id: agent.id,
        reason: reason,
        final_counter: agent.state.counter,
        final_message_count: length(agent.state.messages)
      })

    :ok
  end
end
