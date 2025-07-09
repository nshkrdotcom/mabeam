defmodule Mabeam.Foundation.Communication.EventBus do
  @moduledoc """
  Unified event system for broadcast communication.

  This module provides a centralized event bus for broadcasting
  events to multiple subscribers without expecting responses.
  """

  use GenServer
  require Logger
  alias Mabeam.Debug

  alias Mabeam.Types.Communication.Event
  alias Mabeam.Types.ID

  @type subscription :: {pid(), reference()}
  @type pattern :: binary() | atom() | {:pattern, binary()}

  @type state :: %{
          subscriptions: %{atom() => [subscription()]},
          pattern_subscriptions: %{binary() => [subscription()]},
          event_history: :queue.queue(Event.t()),
          max_history: pos_integer()
        }

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec emit(atom(), term(), map()) :: {:ok, String.t()}
  def emit(event_type, data, metadata \\ %{}) when is_atom(event_type) do
    event = %Event{
      id: ID.event_id() |> ID.unwrap(),
      type: event_type,
      source: self(),
      data: data,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    GenServer.cast(__MODULE__, {:emit, event})

    # Also broadcast via Phoenix.PubSub for distributed systems
    Phoenix.PubSub.broadcast(Mabeam.PubSub, "events:#{event_type}", {:event, event})

    # Emit telemetry
    :telemetry.execute(
      [:mabeam, :events, event_type],
      %{count: 1},
      metadata
    )

    {:ok, event.id}
  end

  @spec subscribe(atom()) :: :ok
  def subscribe(event_type) when is_atom(event_type) do
    GenServer.call(__MODULE__, {:subscribe, event_type, self()})
  end

  @spec subscribe_pattern(binary()) :: :ok
  def subscribe_pattern(pattern) when is_binary(pattern) do
    GenServer.call(__MODULE__, {:subscribe_pattern, pattern, self()})
  end

  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(event_type) when is_atom(event_type) do
    GenServer.call(__MODULE__, {:unsubscribe, event_type, self()})
  end

  @spec unsubscribe_pattern(binary()) :: :ok
  def unsubscribe_pattern(pattern) when is_binary(pattern) do
    GenServer.call(__MODULE__, {:unsubscribe_pattern, pattern, self()})
  end

  @spec get_history(pos_integer()) :: [Event.t()]
  def get_history(limit \\ 100) do
    GenServer.call(__MODULE__, {:get_history, limit})
  end

  ## Server Implementation

  @impl GenServer
  def init(opts) do
    # Start Phoenix.PubSub if not already started
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

    state = %{
      subscriptions: %{},
      pattern_subscriptions: %{},
      event_history: :queue.new(),
      max_history: Keyword.get(opts, :max_history, 1000)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, event_type, pid}, _from, state) do
    ref = Process.monitor(pid)
    subscription = {pid, ref}

    new_subscriptions =
      Map.update(
        state.subscriptions,
        event_type,
        [subscription],
        &[subscription | &1]
      )

    new_state = %{state | subscriptions: new_subscriptions}

    # Subscription added successfully

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:subscribe_pattern, pattern, pid}, _from, state) do
    ref = Process.monitor(pid)
    subscription = {pid, ref}

    new_pattern_subscriptions =
      Map.update(
        state.pattern_subscriptions,
        pattern,
        [subscription],
        &[subscription | &1]
      )

    new_state = %{state | pattern_subscriptions: new_pattern_subscriptions}

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:unsubscribe, event_type, pid}, _from, state) do
    new_subscriptions =
      Map.update(
        state.subscriptions,
        event_type,
        [],
        &Enum.reject(&1, fn {subscriber_pid, ref} ->
          if subscriber_pid == pid do
            Process.demonitor(ref, [:flush])
            true
          else
            false
          end
        end)
      )

    new_state = %{state | subscriptions: new_subscriptions}

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:unsubscribe_pattern, pattern, pid}, _from, state) do
    new_pattern_subscriptions =
      Map.update(
        state.pattern_subscriptions,
        pattern,
        [],
        &Enum.reject(&1, fn {subscriber_pid, ref} ->
          if subscriber_pid == pid do
            Process.demonitor(ref, [:flush])
            true
          else
            false
          end
        end)
      )

    new_state = %{state | pattern_subscriptions: new_pattern_subscriptions}

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:get_history, limit}, _from, state) do
    history =
      state.event_history
      |> :queue.to_list()
      |> Enum.take(-limit)

    {:reply, history, state}
  end

  @impl GenServer
  def handle_cast({:emit, event}, state) do
    # Store in history
    new_history = :queue.in(event, state.event_history)
    trimmed_history = trim_history(new_history, state.max_history)

    # Process event normally

    # Notify exact type subscribers
    case Map.get(state.subscriptions, event.type) do
      nil ->
        Debug.log("No subscribers for event type", event_type: event.type)
        :ok

      subscribers ->
        Debug.log("Notifying subscribers",
          event_type: event.type,
          subscriber_count: length(subscribers),
          event_id: event.id
        )

        Enum.each(subscribers, fn {pid, _ref} ->
          send(pid, {:event, event})
        end)
    end

    # Notify pattern subscribers
    Enum.each(state.pattern_subscriptions, fn {pattern, subscribers} ->
      if event_matches_pattern?(event, pattern) do
        Enum.each(subscribers, fn {pid, _ref} ->
          send(pid, {:event, event})
        end)
      end
    end)

    new_state = %{state | event_history: trimmed_history}

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Remove subscriptions for dead processes
    new_subscriptions =
      Enum.reduce(state.subscriptions, %{}, fn {event_type, subscribers}, acc ->
        filtered_subscribers =
          Enum.reject(subscribers, fn {_pid, subscriber_ref} ->
            subscriber_ref == ref
          end)

        if Enum.empty?(filtered_subscribers) do
          acc
        else
          Map.put(acc, event_type, filtered_subscribers)
        end
      end)

    new_pattern_subscriptions =
      Enum.reduce(state.pattern_subscriptions, %{}, fn {pattern, subscribers}, acc ->
        filtered_subscribers =
          Enum.reject(subscribers, fn {_pid, subscriber_ref} ->
            subscriber_ref == ref
          end)

        if Enum.empty?(filtered_subscribers) do
          acc
        else
          Map.put(acc, pattern, filtered_subscribers)
        end
      end)

    new_state = %{
      state
      | subscriptions: new_subscriptions,
        pattern_subscriptions: new_pattern_subscriptions
    }

    {:noreply, new_state}
  end

  ## Private Functions

  defp trim_history(queue, max_size) do
    case :queue.len(queue) do
      len when len <= max_size ->
        queue

      _len ->
        {{:value, _}, new_queue} = :queue.out(queue)
        trim_history(new_queue, max_size)
    end
  end

  defp event_matches_pattern?(event, pattern) do
    event_type_string = Atom.to_string(event.type)

    case pattern do
      "*" ->
        true

      "**" ->
        true

      pattern_string when is_binary(pattern_string) ->
        # Handle both dots and underscores as separators
        pattern_parts = String.split(pattern_string, ".")
        event_parts = String.split(event_type_string, [".", "_"])
        match_parts(pattern_parts, event_parts)
    end
  end

  defp match_parts([], []), do: true
  defp match_parts(["**"], _), do: true

  defp match_parts([part | pattern_rest], [part | event_rest]),
    do: match_parts(pattern_rest, event_rest)

  # Handle "*" patterns
  defp match_parts(["*" | pattern_rest], event_parts) when length(event_parts) > 0 do
    case pattern_rest do
      # "*" at the end matches any remaining parts
      [] ->
        true

      _ ->
        # "*" in the middle - try matching with one part consumed
        case event_parts do
          [_ | event_rest] -> match_parts(pattern_rest, event_rest)
          [] -> false
        end
    end
  end

  defp match_parts(_, _), do: false
end
