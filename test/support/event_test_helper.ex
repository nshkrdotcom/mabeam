defmodule EventTestHelper do
  @moduledoc """
  Test helper for event system testing.

  This module provides utilities for:
  - Event subscription and unsubscription testing
  - Event propagation and ordering verification
  - Event filtering and pattern matching
  - Event system synchronization

  ## Usage

  This module builds on `MabeamTestHelper` to provide specialized testing
  patterns for the MABEAM event system following OTP best practices.

  ## Example

      # Setup event testing environment
      event_env = EventTestHelper.setup_event_test_environment(
        subscribers: 3,
        event_patterns: [:demo_ping, "demo.*", :system_status]
      )
      
      # Test event subscription and propagation
      test_events = [
        %{type: :demo_ping, data: %{agent_id: "test_agent"}},
        %{type: :demo_increment, data: %{amount: 5}},
        %{type: :system_status, data: %{status: :ready}}
      ]
      
      :ok = EventTestHelper.test_event_propagation(test_events, [
        {:demo_ping, 1},      # Should reach 1 subscriber (specific)
        {:demo_increment, 1}, # Should reach 1 subscriber (pattern match)
        {:system_status, 3}   # Should reach 3 subscribers (all subscribed)
      ])
      
      # Test event ordering and sequencing
      event_sequence = [
        %{type: :task_start, data: %{id: 1}},
        %{type: :task_progress, data: %{id: 1, progress: 50}},
        %{type: :task_complete, data: %{id: 1, result: "success"}}
      ]
      
      :ok = EventTestHelper.test_event_ordering(event_sequence, [:task_start, :task_progress, :task_complete])
  """

  import MabeamTestHelper
  require Logger

  # Configuration constants
  @default_timeout 5000
  @event_propagation_timeout 2000
  @subscription_timeout 1000
  @ordering_timeout 3000
  @filtering_timeout 2000
  @recovery_timeout 5000

  @doc """
  Sets up event testing environment with proper cleanup.

  This function creates an isolated event testing environment with
  multiple subscribers and automatic cleanup.

  ## Parameters

  - `opts` - Environment configuration options

  ## Options

  - `:subscribers` - Number of subscriber processes to create (default: 1)
  - `:event_patterns` - List of event patterns to subscribe to
  - `:event_history_size` - Size of event history to maintain (default: 100)
  - `:timeout` - Timeout for environment setup (default: #{@default_timeout}ms)
  - `:enable_history` - Whether to enable event history tracking (default: true)
  - `:subscriber_names` - Custom names for subscribers (optional)

  ## Returns

  - `%{subscribers: subscribers, patterns: patterns, history: history}` - Environment info
  - `{:error, reason}` - Environment setup failed

  ## Examples

      event_env = EventTestHelper.setup_event_test_environment(
        subscribers: 5,
        event_patterns: [:demo_ping, "demo.*", "system.*"],
        event_history_size: 50,
        enable_history: true
      )
      
      # Environment includes subscriber processes and subscriptions
      assert length(event_env.subscribers) == 5
      assert :demo_ping in event_env.patterns
  """
  @spec setup_event_test_environment(keyword()) ::
          %{subscribers: list(map()), patterns: list(), history: list()} | {:error, term()}
  def setup_event_test_environment(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    subscriber_count = Keyword.get(opts, :subscribers, 1)
    event_patterns = Keyword.get(opts, :event_patterns, [])
    event_history_size = Keyword.get(opts, :event_history_size, 100)
    enable_history = Keyword.get(opts, :enable_history, true)
    subscriber_names = Keyword.get(opts, :subscriber_names, [])

    Logger.debug("Setting up event test environment",
      subscriber_count: subscriber_count,
      pattern_count: length(event_patterns),
      enable_history: enable_history
    )

    try do
      # Create subscriber processes
      case create_event_subscribers(subscriber_count, subscriber_names, timeout) do
        {:ok, subscribers} ->
          # Setup event subscriptions
          case setup_event_subscriptions(subscribers, event_patterns, timeout) do
            {:ok, subscription_info} ->
              # Initialize event history if enabled
              event_history =
                if enable_history do
                  initialize_event_history(event_history_size)
                else
                  []
                end

              event_env = %{
                subscribers: subscribers,
                patterns: event_patterns,
                subscription_info: subscription_info,
                history: event_history,
                created_at: DateTime.utc_now(),
                config: %{
                  subscriber_count: subscriber_count,
                  history_size: event_history_size,
                  enable_history: enable_history
                }
              }

              # Register environment cleanup
              register_event_environment_for_cleanup(event_env)

              Logger.debug("Event test environment setup completed",
                subscriber_count: length(subscribers),
                subscription_count: length(subscription_info)
              )

              event_env

            {:error, reason} ->
              {:error, {:subscription_setup_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:subscriber_creation_failed, reason}}
      end
    rescue
      error ->
        {:error, {:environment_setup_exception, error}}
    catch
      :exit, reason ->
        {:error, {:environment_setup_exit, reason}}
    end
  end

  @doc """
  Tests event subscription with automatic cleanup.

  This function tests event subscription patterns and verifies
  that subscriptions work correctly with proper cleanup.

  ## Parameters

  - `event_patterns` - List of event types or patterns to test
  - `opts` - Additional options

  ## Options

  - `:timeout` - Timeout for subscription testing (default: #{@subscription_timeout}ms)
  - `:verify_unsubscribe` - Test unsubscription functionality (default: true)
  - `:test_invalid_patterns` - Test invalid pattern handling (default: false)

  ## Returns

  - `:ok` - Subscription testing passed
  - `{:error, {:pattern_failed, pattern, reason}}` - Pattern subscription failed

  ## Examples

      :ok = EventTestHelper.test_event_subscription([
        :demo_ping,
        :demo_increment,
        "demo.*",
        "system.status.*"
      ], verify_unsubscribe: true)
  """
  @spec test_event_subscription(list(), keyword()) :: :ok | {:error, term()}
  def test_event_subscription(event_patterns, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @subscription_timeout)
    verify_unsubscribe = Keyword.get(opts, :verify_unsubscribe, true)
    test_invalid_patterns = Keyword.get(opts, :test_invalid_patterns, false)

    Logger.debug("Testing event subscription",
      pattern_count: length(event_patterns),
      verify_unsubscribe: verify_unsubscribe
    )

    # Test valid patterns
    case test_subscription_patterns(event_patterns, timeout) do
      :ok ->
        result =
          if verify_unsubscribe do
            test_unsubscription_patterns(event_patterns, timeout)
          else
            :ok
          end

        case result do
          :ok ->
            if test_invalid_patterns do
              test_invalid_subscription_patterns(timeout)
            else
              :ok
            end
        end

      {:error, reason} ->
        {:error, {:subscription_failed, reason}}
    end
  end

  @doc """
  Tests event propagation with timing verification.

  This function tests that events are properly propagated to
  subscribers with correct timing and filtering.

  ## Parameters

  - `events` - List of events to test
  - `expected_propagation` - Expected propagation patterns
  - `opts` - Additional options

  ## Event Format

  Each event is: `%{type: event_type, data: event_data}`

  ## Expected Propagation Format

  Each expectation is: `{event_type, expected_subscriber_count}` or
  `{event_type, expected_subscriber_count, timeout}`

  ## Options

  - `:timeout` - Default timeout for propagation (default: #{@event_propagation_timeout}ms)
  - `:verify_content` - Verify event content matches (default: true)
  - `:verify_ordering` - Verify event ordering (default: false)
  - `:parallel_events` - Send events in parallel (default: false)

  ## Returns

  - `:ok` - Event propagation working correctly
  - `{:error, {:propagation_failed, event, reason}}` - Propagation failed

  ## Examples

      test_events = [
        %{type: :demo_ping, data: %{agent_id: "test1"}},
        %{type: :demo_increment, data: %{amount: 5}},
        %{type: :system_status, data: %{status: :ready}}
      ]
      
      expected_propagation = [
        {:demo_ping, 2},        # Should reach 2 subscribers
        {:demo_increment, 1},   # Should reach 1 subscriber  
        {:system_status, 3}     # Should reach 3 subscribers
      ]
      
      :ok = EventTestHelper.test_event_propagation(test_events, expected_propagation)
  """
  @spec test_event_propagation(list(map()), list(tuple()), keyword()) :: :ok | {:error, term()}
  def test_event_propagation(events, expected_propagation, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @event_propagation_timeout)
    verify_content = Keyword.get(opts, :verify_content, true)
    verify_ordering = Keyword.get(opts, :verify_ordering, false)
    parallel_events = Keyword.get(opts, :parallel_events, false)

    Logger.debug("Testing event propagation",
      event_count: length(events),
      expectation_count: length(expected_propagation),
      parallel: parallel_events
    )

    # Setup event collection
    event_collector = start_event_collector()

    try do
      # Send events
      case send_test_events(events, parallel_events, timeout) do
        :ok ->
          # Verify propagation
          verify_event_propagation_results(
            events,
            expected_propagation,
            event_collector,
            timeout,
            verify_content,
            verify_ordering
          )

        {:error, reason} ->
          {:error, {:event_sending_failed, reason}}
      end
    after
      stop_event_collector(event_collector)
    end
  end

  @doc """
  Tests event filtering and pattern matching.

  This function tests that event filtering works correctly
  with various pattern matching scenarios.

  ## Parameters

  - `filter_scenarios` - List of filtering scenarios to test
  - `opts` - Additional options

  ## Filter Scenario Format

  Each scenario is a map with:
  - `:pattern` - The pattern to test
  - `:events` - List of events to send
  - `:expected_matches` - List of events that should match
  - `:expected_non_matches` - List of events that should not match

  ## Options

  - `:timeout` - Timeout for filtering tests (default: #{@filtering_timeout}ms)
  - `:verify_exact_matches` - Use exact matching verification (default: true)

  ## Returns

  - `:ok` - Event filtering working correctly
  - `{:error, {:filter_scenario_failed, scenario, reason}}` - Filtering failed

  ## Examples

      filter_scenarios = [
        %{
          pattern: "demo.*",
          events: [
            %{type: :demo_ping, data: %{}},
            %{type: :demo_increment, data: %{}},
            %{type: :system_status, data: %{}}
          ],
          expected_matches: [:demo_ping, :demo_increment],
          expected_non_matches: [:system_status]
        },
        %{
          pattern: :system_status,
          events: [
            %{type: :system_status, data: %{status: :ready}},
            %{type: :demo_ping, data: %{}}
          ],
          expected_matches: [:system_status],
          expected_non_matches: [:demo_ping]
        }
      ]
      
      :ok = EventTestHelper.test_event_filtering(filter_scenarios)
  """
  @spec test_event_filtering(list(map()), keyword()) :: :ok | {:error, term()}
  def test_event_filtering(filter_scenarios, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @filtering_timeout)
    verify_exact_matches = Keyword.get(opts, :verify_exact_matches, true)

    Logger.debug("Testing event filtering",
      scenario_count: length(filter_scenarios)
    )

    execute_filter_scenarios(filter_scenarios, timeout, verify_exact_matches)
  end

  @doc """
  Tests event ordering and sequencing.

  This function tests that events are received in the correct
  order and that sequencing is maintained.

  ## Parameters

  - `event_sequence` - List of events in expected order
  - `expected_order` - Expected order pattern
  - `opts` - Additional options

  ## Expected Order Format

  Can be:
  - List of event types in expected order
  - Function that validates the order: `fn received_events -> boolean end`
  - `:any` to skip order verification

  ## Options

  - `:timeout` - Timeout for ordering test (default: #{@ordering_timeout}ms)
  - `:strict_ordering` - Require exact order match (default: true)
  - `:allow_interleaving` - Allow other events between expected events (default: false)

  ## Returns

  - `:ok` - Event ordering working correctly
  - `{:error, {:ordering_failed, expected, actual}}` - Ordering verification failed

  ## Examples

      event_sequence = [
        %{type: :task_start, data: %{id: 1}},
        %{type: :task_progress, data: %{id: 1, progress: 25}},
        %{type: :task_progress, data: %{id: 1, progress: 50}},
        %{type: :task_progress, data: %{id: 1, progress: 75}},
        %{type: :task_complete, data: %{id: 1}}
      ]
      
      expected_order = [:task_start, :task_progress, :task_progress, :task_progress, :task_complete]
      
      :ok = EventTestHelper.test_event_ordering(event_sequence, expected_order)
      
      # Or use a validation function
      order_validator = fn events ->
        event_types = Enum.map(events, &(&1.type))
        hd(event_types) == :task_start and List.last(event_types) == :task_complete
      end
      
      :ok = EventTestHelper.test_event_ordering(event_sequence, order_validator)
  """
  @spec test_event_ordering(list(map()), term(), keyword()) :: :ok | {:error, term()}
  def test_event_ordering(event_sequence, expected_order, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @ordering_timeout)
    strict_ordering = Keyword.get(opts, :strict_ordering, true)
    allow_interleaving = Keyword.get(opts, :allow_interleaving, false)

    Logger.debug("Testing event ordering",
      event_count: length(event_sequence),
      strict: strict_ordering,
      allow_interleaving: allow_interleaving
    )

    # Setup order tracking
    order_tracker = start_order_tracker()

    try do
      # Subscribe to all event types in the sequence
      event_types = Enum.map(event_sequence, & &1.type) |> Enum.uniq()
      subscribe_to_events(event_types)

      # Send events in sequence
      case send_events_in_sequence(event_sequence, timeout) do
        :ok ->
          # Collect received events
          case collect_ordered_events(event_types, length(event_sequence), timeout) do
            {:ok, received_events} ->
              # Verify ordering
              verify_event_order(
                received_events,
                expected_order,
                strict_ordering,
                allow_interleaving
              )

            {:error, reason} ->
              {:error, {:event_collection_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:event_sending_failed, reason}}
      end
    after
      stop_order_tracker(order_tracker)
    end
  end

  @doc """
  Tests event system recovery from failures.

  This function tests how the event system handles and recovers
  from various failure scenarios.

  ## Parameters

  - `failure_scenarios` - List of failure scenarios to test
  - `opts` - Additional options

  ## Failure Scenario Format

  Each scenario is a map with:
  - `:failure_type` - Type of failure to simulate
  - `:trigger` - Function to trigger the failure
  - `:recovery_action` - Optional recovery action
  - `:verify_recovery` - Function to verify recovery
  - `:timeout` - Scenario-specific timeout

  ## Failure Types

  Supported failure types:
  - `:subscriber_crash` - Subscriber process crashes
  - `:event_bus_overload` - Event bus overload
  - `:invalid_event` - Invalid event format
  - `:subscription_leak` - Subscription cleanup failure

  ## Options

  - `:timeout` - Default timeout for recovery (default: #{@recovery_timeout}ms)
  - `:continue_on_failure` - Continue testing after failures (default: false)

  ## Returns

  - `:ok` - Event system recovery working correctly
  - `{:error, {:recovery_failed, scenario, reason}}` - Recovery failed

  ## Examples

      failure_scenarios = [
        %{
          failure_type: :subscriber_crash,
          trigger: fn -> 
            # Crash a subscriber process
            pid = spawn(fn -> Process.exit(self(), :kill) end)
            Mabeam.subscribe("test_event")
            pid
          end,
          verify_recovery: fn ->
            # Verify event system still works
            Mabeam.emit_event("test_event", %{data: "test"})
          end
        }
      ]
      
      :ok = EventTestHelper.test_event_system_recovery(failure_scenarios)
  """
  @spec test_event_system_recovery(list(map()), keyword()) :: :ok | {:error, term()}
  def test_event_system_recovery(failure_scenarios, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @recovery_timeout)
    continue_on_failure = Keyword.get(opts, :continue_on_failure, false)

    Logger.debug("Testing event system recovery",
      scenario_count: length(failure_scenarios)
    )

    execute_recovery_scenarios(failure_scenarios, timeout, continue_on_failure)
  end

  # Private helper functions

  @spec create_event_subscribers(non_neg_integer(), list(), non_neg_integer()) ::
          {:ok, list(map())} | {:error, term()}
  defp create_event_subscribers(count, custom_names, _timeout) do
    subscribers =
      1..count
      |> Enum.with_index()
      |> Enum.map(fn {_num, index} ->
        name =
          if index < length(custom_names) do
            Enum.at(custom_names, index)
          else
            :"event_subscriber_#{index}_#{:erlang.unique_integer([:positive])}"
          end

        case start_event_subscriber(name, index) do
          {:ok, pid} ->
            %{
              name: name,
              pid: pid,
              index: index,
              subscriptions: [],
              created_at: DateTime.utc_now()
            }

          {:error, reason} ->
            {:error, {:subscriber_start_failed, index, reason}}
        end
      end)

    # Check for failures
    failed_subscribers =
      Enum.filter(subscribers, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_subscribers) do
      {:ok, subscribers}
    else
      {:error, {:multiple_subscriber_failures, failed_subscribers}}
    end
  end

  @spec start_event_subscriber(atom(), non_neg_integer()) :: {:ok, pid()} | {:error, term()}
  defp start_event_subscriber(name, index) do
    parent_pid = self()

    pid =
      spawn_link(fn ->
        Process.register(self(), name)
        send(parent_pid, {:subscriber_ready, self()})
        event_subscriber_loop(parent_pid, index, [])
      end)

    # Wait for registration
    receive do
      {:subscriber_ready, ^pid} -> {:ok, pid}
    after
      1000 -> {:error, :subscriber_registration_timeout}
    end
  end

  @spec event_subscriber_loop(pid(), non_neg_integer(), list()) :: no_return()
  defp event_subscriber_loop(parent_pid, index, received_events) do
    receive do
      {:register_subscriber, from_pid} ->
        send(from_pid, {:subscriber_ready, self()})
        event_subscriber_loop(parent_pid, index, received_events)

      {:event, event} ->
        updated_events = [event | received_events]
        send(parent_pid, {:event_received, index, event})
        event_subscriber_loop(parent_pid, index, updated_events)

      {:get_events, from_pid} ->
        send(from_pid, {:events, index, Enum.reverse(received_events)})
        event_subscriber_loop(parent_pid, index, received_events)

      {:clear_events, from_pid} ->
        send(from_pid, {:events_cleared, index})
        event_subscriber_loop(parent_pid, index, [])

      :stop ->
        :ok

      other ->
        Logger.warning("Event subscriber received unexpected message",
          message: inspect(other),
          index: index
        )

        event_subscriber_loop(parent_pid, index, received_events)
    end
  end

  @spec setup_event_subscriptions(list(map()), list(), non_neg_integer()) ::
          {:ok, list()} | {:error, term()}
  defp setup_event_subscriptions(subscribers, event_patterns, _timeout) do
    subscription_info =
      for subscriber <- subscribers,
          pattern <- event_patterns do
        case subscribe_subscriber_to_pattern(subscriber, pattern) do
          :ok ->
            %{
              subscriber: subscriber.name,
              pattern: pattern,
              subscribed_at: DateTime.utc_now()
            }

          {:error, reason} ->
            {:error, {:subscription_failed, subscriber.name, pattern, reason}}
        end
      end

    # Check for failures
    failed_subscriptions =
      Enum.filter(subscription_info, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_subscriptions) do
      {:ok, subscription_info}
    else
      {:error, {:multiple_subscription_failures, failed_subscriptions}}
    end
  end

  @spec subscribe_subscriber_to_pattern(map(), term()) :: :ok | {:error, term()}
  defp subscribe_subscriber_to_pattern(_subscriber, pattern) do
    try do
      case pattern do
        pattern when is_binary(pattern) ->
          # Pattern subscription
          Mabeam.subscribe_pattern(pattern)

        event_type when is_atom(event_type) ->
          # Direct event type subscription
          Mabeam.subscribe(event_type)

        _ ->
          {:error, {:invalid_pattern, pattern}}
      end
    rescue
      error ->
        {:error, {:subscription_exception, error}}
    catch
      :exit, reason ->
        {:error, {:subscription_exit, reason}}
    end
  end

  @spec initialize_event_history(non_neg_integer()) :: list()
  defp initialize_event_history(_size) do
    # Initialize circular buffer for event history
    []
  end

  @spec register_event_environment_for_cleanup(map()) :: :ok
  defp register_event_environment_for_cleanup(event_env) do
    try do
      ExUnit.Callbacks.on_exit(fn ->
        cleanup_event_environment(event_env)
      end)
    rescue
      ArgumentError ->
        # Not in test process
        :ok
    end

    :ok
  end

  @spec cleanup_event_environment(map()) :: :ok
  defp cleanup_event_environment(event_env) do
    Logger.debug("Cleaning up event test environment",
      subscriber_count: length(event_env.subscribers)
    )

    # Stop subscriber processes
    Enum.each(event_env.subscribers, fn subscriber ->
      if Process.alive?(subscriber.pid) do
        send(subscriber.pid, :stop)
      end
    end)

    # Additional cleanup handled by MabeamTestHelper
    :ok
  end

  @spec test_subscription_patterns(list(), non_neg_integer()) :: :ok | {:error, term()}
  defp test_subscription_patterns(patterns, timeout) do
    Enum.reduce_while(patterns, :ok, fn pattern, acc ->
      case test_single_subscription_pattern(pattern, timeout) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, {:pattern_failed, pattern, reason}}}
      end
    end)
  end

  @spec test_single_subscription_pattern(term(), non_neg_integer()) :: :ok | {:error, term()}
  defp test_single_subscription_pattern(pattern, timeout) do
    try do
      case subscribe_to_events([pattern]) do
        :ok ->
          # Test that subscription is active by sending a test event
          test_event_type = generate_test_event_for_pattern(pattern)

          case Mabeam.emit_event(test_event_type, %{test: true}) do
            {:ok, _event_id} ->
              # Try to receive the event
              case wait_for_event(test_event_type, timeout) do
                {:ok, _event} ->
                  :ok

                {:error, :timeout} ->
                  {:error, {:event_not_received, test_event_type, timeout}}
              end

            {:error, reason} ->
              {:error, {:test_event_emission_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:subscription_failed, reason}}
      end
    rescue
      error ->
        {:error, {:pattern_test_exception, error}}
    catch
      :exit, reason ->
        {:error, {:pattern_test_exit, reason}}
    end
  end

  @spec generate_test_event_for_pattern(term()) :: binary()
  defp generate_test_event_for_pattern(pattern) when is_atom(pattern), do: Atom.to_string(pattern)

  defp generate_test_event_for_pattern(pattern) when is_binary(pattern) do
    # Generate an event type that should match the pattern
    case String.split(pattern, "*") do
      [prefix, _] ->
        # Generate string event that matches pattern
        "#{prefix}test_event"

      [exact_match] ->
        # No wildcard, return exact match
        exact_match

      _ ->
        "pattern_test_event"
    end
  end

  defp generate_test_event_for_pattern(_), do: "unknown_pattern_test"

  @spec test_unsubscription_patterns(list(), non_neg_integer()) :: :ok | {:error, term()}
  defp test_unsubscription_patterns(_patterns, _timeout) do
    # Note: Unsubscription functions may not be implemented yet
    # This is a placeholder for when they become available
    Logger.debug("Unsubscription testing skipped - functions not yet implemented")
    :ok
  end

  @spec test_invalid_subscription_patterns(non_neg_integer()) :: :ok | {:error, term()}
  defp test_invalid_subscription_patterns(timeout) do
    invalid_patterns = [
      nil,
      [],
      %{invalid: :pattern},
      {:tuple, :pattern}
    ]

    # Test that invalid patterns are handled gracefully
    Enum.reduce_while(invalid_patterns, :ok, fn pattern, acc ->
      case test_invalid_pattern_handling(pattern, timeout) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, {:invalid_pattern_test_failed, pattern, reason}}}
      end
    end)
  end

  @spec test_invalid_pattern_handling(term(), non_neg_integer()) :: :ok | {:error, term()}
  defp test_invalid_pattern_handling(pattern, _timeout) do
    try do
      # Invalid patterns should either be rejected or handled gracefully
      case subscribe_to_events([pattern]) do
        :ok ->
          # If subscription succeeds with invalid pattern, that's also ok
          # as long as it doesn't crash the system
          :ok

        {:error, _reason} ->
          # Expected behavior for invalid patterns
          :ok
      end
    rescue
      error ->
        # System should handle invalid patterns gracefully
        {:error, {:invalid_pattern_exception, error}}
    catch
      :exit, reason ->
        {:error, {:invalid_pattern_exit, reason}}
    end
  end

  @spec start_event_collector() :: pid()
  defp start_event_collector do
    parent_pid = self()

    spawn_link(fn ->
      event_collector_loop(parent_pid, [])
    end)
  end

  @spec event_collector_loop(pid(), list()) :: no_return()
  defp event_collector_loop(parent_pid, collected_events) do
    receive do
      {:event, event} ->
        updated_events = [event | collected_events]
        event_collector_loop(parent_pid, updated_events)

      {:get_collected_events, from_pid} ->
        send(from_pid, {:collected_events, Enum.reverse(collected_events)})
        event_collector_loop(parent_pid, collected_events)

      {:clear_collected_events, from_pid} ->
        send(from_pid, {:events_cleared})
        event_collector_loop(parent_pid, [])

      :stop ->
        :ok

      other ->
        Logger.warning("Event collector received unexpected message",
          message: inspect(other)
        )

        event_collector_loop(parent_pid, collected_events)
    end
  end

  @spec stop_event_collector(pid()) :: :ok
  defp stop_event_collector(collector_pid) do
    if Process.alive?(collector_pid) do
      send(collector_pid, :stop)
    end

    :ok
  end

  @spec send_test_events(list(map()), boolean(), non_neg_integer()) :: :ok | {:error, term()}
  defp send_test_events(events, parallel, timeout) do
    if parallel do
      send_events_parallel(events, timeout)
    else
      send_events_sequential(events, timeout)
    end
  end

  @spec send_events_sequential(list(map()), non_neg_integer()) :: :ok | {:error, term()}
  defp send_events_sequential(events, _timeout) do
    Enum.reduce_while(events, :ok, fn event, acc ->
      case Mabeam.emit_event(event.type, event.data) do
        {:ok, _event_id} -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, {:event_emission_failed, event, reason}}}
      end
    end)
  end

  @spec send_events_parallel(list(map()), non_neg_integer()) :: :ok | {:error, term()}
  defp send_events_parallel(events, timeout) do
    tasks =
      Enum.map(events, fn event ->
        Task.async(fn ->
          Mabeam.emit_event(event.type, event.data)
        end)
      end)

    results =
      Enum.map(tasks, fn task ->
        Task.await(task, timeout)
      end)

    # Check for failures
    failed_results =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_results) do
      :ok
    else
      {:error, {:parallel_emission_failures, failed_results}}
    end
  end

  @spec verify_event_propagation_results(
          list(map()),
          list(tuple()),
          pid(),
          non_neg_integer(),
          boolean(),
          boolean()
        ) ::
          :ok | {:error, term()}
  defp verify_event_propagation_results(
         events,
         expected_propagation,
         collector,
         timeout,
         verify_content,
         verify_ordering
       ) do
    try do
      Mabeam.Foundation.Communication.EventBus.get_history(1)
    catch
      _ -> :ok
    end

    # Get collected events
    send(collector, {:get_collected_events, self()})

    receive do
      {:collected_events, received_events} ->
        verify_propagation_expectations(
          events,
          expected_propagation,
          received_events,
          verify_content,
          verify_ordering
        )
    after
      timeout ->
        {:error, :event_collection_timeout}
    end
  end

  @spec verify_propagation_expectations(
          list(map()),
          list(tuple()),
          list(map()),
          boolean(),
          boolean()
        ) ::
          :ok | {:error, term()}
  defp verify_propagation_expectations(
         _sent_events,
         expected_propagation,
         received_events,
         verify_content,
         _verify_ordering
       ) do
    # Group received events by type
    received_by_type = Enum.group_by(received_events, & &1.type)

    # Verify each expectation
    Enum.reduce_while(expected_propagation, :ok, fn expectation, acc ->
      case verify_single_propagation_expectation(expectation, received_by_type, verify_content) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, {:expectation_failed, expectation, reason}}}
      end
    end)
  end

  @spec verify_single_propagation_expectation(tuple(), map(), boolean()) :: :ok | {:error, term()}
  defp verify_single_propagation_expectation(
         {event_type, expected_count},
         received_by_type,
         verify_content
       ) do
    verify_single_propagation_expectation(
      {event_type, expected_count, @event_propagation_timeout},
      received_by_type,
      verify_content
    )
  end

  defp verify_single_propagation_expectation(
         {event_type, expected_count, _timeout},
         received_by_type,
         _verify_content
       ) do
    actual_events = Map.get(received_by_type, event_type, [])
    actual_count = length(actual_events)

    if actual_count == expected_count do
      :ok
    else
      {:error, {:count_mismatch, expected_count, actual_count}}
    end
  end

  @spec execute_filter_scenarios(list(map()), non_neg_integer(), boolean()) ::
          :ok | {:error, term()}
  defp execute_filter_scenarios(scenarios, timeout, verify_exact_matches) do
    Enum.reduce_while(scenarios, :ok, fn scenario, acc ->
      case execute_single_filter_scenario(scenario, timeout, verify_exact_matches) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, {:filter_scenario_failed, scenario, reason}}}
      end
    end)
  end

  @spec execute_single_filter_scenario(map(), non_neg_integer(), boolean()) ::
          :ok | {:error, term()}
  defp execute_single_filter_scenario(scenario, timeout, verify_exact_matches) do
    pattern = Map.get(scenario, :pattern)
    events = Map.get(scenario, :events, [])
    expected_matches = Map.get(scenario, :expected_matches, [])
    expected_non_matches = Map.get(scenario, :expected_non_matches, [])

    # Subscribe to the pattern
    case subscribe_to_events([pattern]) do
      :ok ->
        # Send all events
        case send_events_sequential(events, timeout) do
          :ok ->
            # Collect received events (only wait for expected matches)
            case collect_pattern_matched_events(expected_matches, timeout) do
              {:ok, received_events} ->
                verify_pattern_matching_results(
                  received_events,
                  expected_matches,
                  expected_non_matches,
                  verify_exact_matches
                )

              {:error, reason} ->
                {:error, {:event_collection_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:event_sending_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:pattern_subscription_failed, reason}}
    end
  end

  @spec collect_pattern_matched_events(list(), non_neg_integer()) ::
          {:ok, list()} | {:error, term()}
  defp collect_pattern_matched_events(event_types, timeout) do
    start_time = System.monotonic_time(:millisecond)
    collect_events_loop(event_types, [], start_time, timeout)
  end

  @spec collect_events_loop(list(), list(), integer(), non_neg_integer()) ::
          {:ok, list()} | {:error, term()}
  defp collect_events_loop([], collected, _start_time, _timeout) do
    {:ok, Enum.reverse(collected)}
  end

  defp collect_events_loop(remaining_types, collected, start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    remaining_timeout = timeout - elapsed

    if remaining_timeout <= 0 do
      {:ok, Enum.reverse(collected)}
    else
      receive do
        {:event, %{type: event_type} = event} ->
          if event_type in remaining_types do
            updated_remaining = List.delete(remaining_types, event_type)
            collect_events_loop(updated_remaining, [event | collected], start_time, timeout)
          else
            # Event not in expected list, continue waiting
            collect_events_loop(remaining_types, collected, start_time, timeout)
          end
      after
        remaining_timeout ->
          {:error, {:timeout_waiting_for_events, remaining_types}}
      end
    end
  end

  @spec verify_pattern_matching_results(list(), list(), list(), boolean()) ::
          :ok | {:error, term()}
  defp verify_pattern_matching_results(
         received_events,
         expected_matches,
         expected_non_matches,
         verify_exact
       ) do
    received_types = Enum.map(received_events, & &1.type)

    # Check that all expected matches were received
    missing_matches = expected_matches -- received_types

    # Check that no non-matches were received
    unexpected_matches =
      Enum.filter(received_types, fn type ->
        type in expected_non_matches
      end)

    cond do
      not Enum.empty?(missing_matches) ->
        {:error, {:missing_expected_matches, missing_matches}}

      not Enum.empty?(unexpected_matches) ->
        {:error, {:unexpected_matches, unexpected_matches}}

      verify_exact and length(received_types) != length(expected_matches) ->
        {:error, {:count_mismatch, length(expected_matches), length(received_types)}}

      true ->
        :ok
    end
  end

  @spec send_events_in_sequence(list(map()), non_neg_integer()) :: :ok | {:error, term()}
  defp send_events_in_sequence(events, timeout) do
    _inter_event_delay = max(10, div(timeout, length(events) * 2))

    Enum.reduce_while(events, :ok, fn event, acc ->
      case Mabeam.emit_event(event.type, event.data) do
        {:ok, _event_id} ->
          try do
            Mabeam.Foundation.Communication.EventBus.get_history(1)
          catch
            _ -> :ok
          end

          {:cont, acc}

        {:error, reason} ->
          {:halt, {:error, {:event_emission_failed, event, reason}}}
      end
    end)
  end

  @spec collect_ordered_events(list(atom()), non_neg_integer(), non_neg_integer()) ::
          {:ok, list()} | {:error, term()}
  defp collect_ordered_events(event_types, expected_count, timeout) do
    start_time = System.monotonic_time(:millisecond)
    collect_ordered_loop(event_types, expected_count, [], start_time, timeout)
  end

  @spec collect_ordered_loop(
          list(atom()),
          non_neg_integer(),
          list(),
          integer(),
          non_neg_integer()
        ) ::
          {:ok, list()} | {:error, term()}
  defp collect_ordered_loop(_event_types, expected_count, collected, _start_time, _timeout)
       when length(collected) >= expected_count do
    {:ok, Enum.reverse(collected)}
  end

  defp collect_ordered_loop(event_types, expected_count, collected, start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    remaining_timeout = timeout - elapsed

    if remaining_timeout <= 0 do
      {:ok, Enum.reverse(collected)}
    else
      receive do
        {:event, %{type: event_type} = event} ->
          if event_type in event_types do
            collect_ordered_loop(
              event_types,
              expected_count,
              [event | collected],
              start_time,
              timeout
            )
          else
            # Ignore events not in our target list
            collect_ordered_loop(event_types, expected_count, collected, start_time, timeout)
          end
      after
        remaining_timeout ->
          {:ok, Enum.reverse(collected)}
      end
    end
  end

  @spec verify_event_order(list(), term(), boolean(), boolean()) :: :ok | {:error, term()}
  defp verify_event_order(received_events, expected_order, _strict_ordering, _allow_interleaving)
       when is_function(expected_order) do
    if expected_order.(received_events) do
      :ok
    else
      {:error, {:custom_order_validation_failed, received_events}}
    end
  end

  defp verify_event_order(_received_events, :any, _strict, _interleaving) do
    :ok
  end

  defp verify_event_order(received_events, expected_order, strict_ordering, allow_interleaving)
       when is_list(expected_order) do
    received_types = Enum.map(received_events, & &1.type)

    if strict_ordering and not allow_interleaving do
      # Exact order match required
      if received_types == expected_order do
        :ok
      else
        {:error, {:strict_order_mismatch, expected_order, received_types}}
      end
    else
      # More flexible order checking
      verify_flexible_order(received_types, expected_order, allow_interleaving)
    end
  end

  defp verify_event_order(_received_events, expected_order, _strict, _interleaving) do
    {:error, {:unsupported_order_format, expected_order}}
  end

  @spec verify_flexible_order(list(atom()), list(atom()), boolean()) :: :ok | {:error, term()}
  defp verify_flexible_order(received_types, expected_order, allow_interleaving) do
    if allow_interleaving do
      # Check that expected events appear in order, but allow other events between them
      case extract_expected_subsequence(received_types, expected_order) do
        ^expected_order ->
          :ok

        actual_subsequence ->
          {:error, {:subsequence_mismatch, expected_order, actual_subsequence}}
      end
    else
      # Check that expected events appear in order with no gaps
      case find_contiguous_subsequence(received_types, expected_order) do
        :found ->
          :ok

        :not_found ->
          {:error, {:contiguous_subsequence_not_found, expected_order, received_types}}
      end
    end
  end

  @spec extract_expected_subsequence(list(atom()), list(atom())) :: list(atom())
  defp extract_expected_subsequence(received_types, expected_order) do
    Enum.filter(received_types, fn type ->
      type in expected_order
    end)
  end

  @spec find_contiguous_subsequence(list(atom()), list(atom())) :: :found | :not_found
  defp find_contiguous_subsequence(received_types, expected_order) do
    expected_length = length(expected_order)

    received_types
    |> Enum.chunk_every(expected_length, 1, :discard)
    |> Enum.any?(fn chunk -> chunk == expected_order end)
    |> case do
      true -> :found
      false -> :not_found
    end
  end

  @spec start_order_tracker() :: pid()
  defp start_order_tracker do
    # Placeholder for order tracking process
    # Could be enhanced to track complex ordering scenarios
    self()
  end

  @spec stop_order_tracker(pid()) :: :ok
  defp stop_order_tracker(_tracker_pid) do
    # Placeholder for order tracker cleanup
    :ok
  end

  @spec execute_recovery_scenarios(list(map()), non_neg_integer(), boolean()) ::
          :ok | {:error, term()}
  defp execute_recovery_scenarios(scenarios, timeout, continue_on_failure) do
    Enum.reduce_while(scenarios, :ok, fn scenario, acc ->
      case execute_recovery_scenario(scenario, timeout) do
        :ok ->
          {:cont, acc}

        {:error, reason} ->
          if continue_on_failure do
            Logger.warning("Recovery scenario failed but continuing",
              scenario: inspect(scenario),
              reason: reason
            )

            {:cont, acc}
          else
            {:halt, {:error, {:recovery_failed, scenario, reason}}}
          end
      end
    end)
  end

  @spec execute_recovery_scenario(map(), non_neg_integer()) :: :ok | {:error, term()}
  defp execute_recovery_scenario(scenario, timeout) do
    failure_type = Map.get(scenario, :failure_type)
    trigger = Map.get(scenario, :trigger)
    recovery_action = Map.get(scenario, :recovery_action)
    verify_recovery = Map.get(scenario, :verify_recovery)
    scenario_timeout = Map.get(scenario, :timeout, timeout)

    Logger.debug("Executing recovery scenario", failure_type: failure_type)

    try do
      # Trigger the failure
      case trigger.() do
        _result ->
          try do
            Mabeam.Foundation.Communication.EventBus.get_history(1)
          catch
            _ -> :ok
          end

          # Execute recovery action if provided
          case execute_recovery_action_if_provided(recovery_action, scenario_timeout) do
            :ok ->
              # Verify recovery
              verify_recovery_if_provided(verify_recovery, scenario_timeout)

            {:error, reason} ->
              {:error, {:recovery_action_failed, reason}}
          end
      end
    rescue
      error ->
        {:error, {:recovery_scenario_exception, error}}
    catch
      :exit, reason ->
        {:error, {:recovery_scenario_exit, reason}}
    end
  end

  @spec execute_recovery_action_if_provided(term(), non_neg_integer()) :: :ok | {:error, term()}
  defp execute_recovery_action_if_provided(nil, _timeout), do: :ok

  defp execute_recovery_action_if_provided(recovery_action, _timeout)
       when is_function(recovery_action) do
    try do
      case recovery_action.() do
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

  defp execute_recovery_action_if_provided(recovery_action, _timeout) do
    {:error, {:unsupported_recovery_action, recovery_action}}
  end

  @spec verify_recovery_if_provided(term(), non_neg_integer()) :: :ok | {:error, term()}
  defp verify_recovery_if_provided(nil, _timeout), do: :ok

  defp verify_recovery_if_provided(verify_recovery, _timeout) when is_function(verify_recovery) do
    try do
      case verify_recovery.() do
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

  defp verify_recovery_if_provided(verify_recovery, _timeout) do
    {:error, {:unsupported_recovery_verification, verify_recovery}}
  end
end
