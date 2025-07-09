defmodule Mabeam.Foundation.Communication.EventBusTest do
  use ExUnit.Case
  alias Mabeam.Foundation.Communication.EventBus
  alias Mabeam.Types.Communication.Event

  setup do
    # Use the existing event bus from the application
    # EventBus is already started and registered as __MODULE__
    %{event_bus: EventBus}
  end

  describe "emit/3" do
    test "emits an event successfully" do
      {:ok, event_id} = EventBus.emit(:test_event, %{data: "test"}, %{source: "test"})

      assert is_binary(event_id)
    end

    test "creates proper event structure" do
      # Subscribe to catch the event
      EventBus.subscribe(:test_event)

      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"}, %{source: "test"})

      # Should receive the event
      assert_receive {:event, %Event{} = event}
      assert event.type == :test_event
      assert event.data == %{data: "test"}
      assert event.metadata == %{source: "test"}
      assert %DateTime{} = event.timestamp
    end
  end

  describe "subscribe/1" do
    test "subscribes to specific event types" do
      assert :ok = EventBus.subscribe(:test_event)

      # Emit an event
      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"})

      # Should receive the event
      assert_receive {:event, %Event{type: :test_event}}

      # Should not receive other events
      {:ok, _event_id} = EventBus.emit(:other_event, %{data: "test"})
      refute_receive {:event, %Event{type: :other_event}}, 100
    end

    test "multiple subscribers receive the same event" do
      # Subscribe from two different processes
      parent = self()

      subscriber1 =
        spawn(fn ->
          EventBus.subscribe(:test_event)
          send(parent, {:ready, :subscriber1})

          receive do
            {:event, event} -> send(parent, {:subscriber1, event})
          end
        end)

      subscriber2 =
        spawn(fn ->
          EventBus.subscribe(:test_event)
          send(parent, {:ready, :subscriber2})

          receive do
            {:event, event} -> send(parent, {:subscriber2, event})
          end
        end)

      # Wait for subscribers to be ready
      assert_receive {:ready, :subscriber1}
      assert_receive {:ready, :subscriber2}

      # Emit event
      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"})

      # Both should receive
      assert_receive {:subscriber1, %Event{type: :test_event}}
      assert_receive {:subscriber2, %Event{type: :test_event}}

      # Clean up
      Process.exit(subscriber1, :normal)
      Process.exit(subscriber2, :normal)
    end
  end

  describe "subscribe_pattern/1" do
    test "subscribes to events matching a pattern" do
      assert :ok = EventBus.subscribe_pattern("test.*")

      # Should receive matching events
      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"})
      assert_receive {:event, %Event{type: :test_event}}

      {:ok, _event_id} = EventBus.emit(:test_action, %{data: "test"})
      assert_receive {:event, %Event{type: :test_action}}

      # Should not receive non-matching events
      {:ok, _event_id} = EventBus.emit(:other_event, %{data: "test"})
      refute_receive {:event, %Event{type: :other_event}}, 100
    end

    test "supports wildcard patterns" do
      assert :ok = EventBus.subscribe_pattern("*")

      # Should receive all events
      {:ok, _event_id} = EventBus.emit(:any_event, %{data: "test"})
      assert_receive {:event, %Event{type: :any_event}}

      {:ok, _event_id} = EventBus.emit(:another_event, %{data: "test"})
      assert_receive {:event, %Event{type: :another_event}}
    end
  end

  describe "unsubscribe/1" do
    test "unsubscribes from specific event types" do
      assert :ok = EventBus.subscribe(:test_event)

      # Should receive event
      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"})
      assert_receive {:event, %Event{type: :test_event}}

      # Unsubscribe
      assert :ok = EventBus.unsubscribe(:test_event)

      # Should not receive event after unsubscribe
      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"})
      refute_receive {:event, %Event{type: :test_event}}, 100
    end
  end

  describe "get_history/1" do
    test "returns event history" do
      # Get initial history length (may have events from other tests)
      initial_history = EventBus.get_history()
      initial_count = length(initial_history)

      # Emit some events
      {:ok, _event_id1} = EventBus.emit(:event1, %{data: "test1"})
      {:ok, _event_id2} = EventBus.emit(:event2, %{data: "test2"})

      # Should have history
      history = EventBus.get_history()
      assert length(history) == initial_count + 2

      # Should be in order (get the last two events)
      last_two = Enum.take(history, -2)
      assert Enum.at(last_two, 0).type == :event1
      assert Enum.at(last_two, 1).type == :event2
    end

    test "limits history size" do
      # Emit many events
      Enum.each(1..5, fn i ->
        {:ok, _event_id} = EventBus.emit(:"event#{i}", %{data: "test#{i}"})
      end)

      # Get limited history
      history = EventBus.get_history(3)
      assert length(history) == 3

      # Should be the last 3 events
      assert Enum.at(history, 0).type == :event3
      assert Enum.at(history, 1).type == :event4
      assert Enum.at(history, 2).type == :event5
    end
  end

  describe "process monitoring" do
    test "removes dead process subscriptions" do
      # Create a subscriber process
      parent = self()

      subscriber =
        spawn(fn ->
          EventBus.subscribe(:test_event)
          send(parent, :subscribed)

          receive do
            :die -> exit(:normal)
          end
        end)

      # Wait for subscription
      assert_receive :subscribed

      # Kill the subscriber
      send(subscriber, :die)
      # Give time for cleanup
      Process.sleep(10)

      # Emit event - should not crash even though subscriber is dead
      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"})

      # Event bus should still be alive
      event_bus_pid = Process.whereis(EventBus)
      assert Process.alive?(event_bus_pid)
    end
  end

  describe "Phoenix.PubSub integration" do
    test "also broadcasts via Phoenix.PubSub" do
      # Subscribe via Phoenix.PubSub
      Phoenix.PubSub.subscribe(Mabeam.PubSub, "events:test_event")

      # Emit event
      {:ok, _event_id} = EventBus.emit(:test_event, %{data: "test"})

      # Should receive via Phoenix.PubSub
      assert_receive {:event, %Event{type: :test_event}}
    end
  end
end
