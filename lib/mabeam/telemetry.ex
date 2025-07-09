defmodule Mabeam.Telemetry do
  @moduledoc """
  Telemetry setup for Mabeam.

  This module sets up telemetry handlers for all foundation components
  to provide comprehensive observability.
  """

  use Supervisor
  require Logger
  alias Mabeam.Debug

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    # Setup telemetry handlers
    setup_telemetry()

    # No children for now - just setup handlers
    Supervisor.init([], strategy: :one_for_one)
  end

  defp setup_telemetry do
    events = [
      # Agent events
      [:mabeam, :agent, :lifecycle, :started],
      [:mabeam, :agent, :lifecycle, :stopped],
      [:mabeam, :agent, :lifecycle, :stopping],
      [:mabeam, :agent, :lifecycle, :start_failed],
      [:mabeam, :agent, :lifecycle, :stop_failed],

      # Registry events
      [:mabeam, :registry, :register],
      [:mabeam, :registry, :unregister],

      # Event bus events
      [:mabeam, :events, :*],

      # Foundation events
      [:mabeam, :foundation, :*]
    ]

    :telemetry.attach_many(
      "mabeam_telemetry",
      events,
      &handle_event/4,
      %{}
    )

    Logger.info("Mabeam telemetry handlers attached")
  end

  defp handle_event(event_name, measurements, metadata, _config) do
    # Log important events
    case event_name do
      [:mabeam, :agent, :lifecycle, :started] ->
        Logger.info("Agent started",
          agent_id: metadata.agent_id,
          agent_type: metadata.agent_type
        )

      [:mabeam, :agent, :lifecycle, :stopped] ->
        Logger.info("Agent stopped",
          agent_id: metadata.agent_id,
          reason: metadata.reason
        )

      [:mabeam, :agent, :lifecycle, :start_failed] ->
        Logger.error("Agent start failed",
          agent_id: metadata.agent_id,
          reason: metadata.reason
        )

      [:mabeam, :registry, :register] ->
        Debug.log("Agent registered",
          agent_id: metadata.agent_id,
          agent_type: metadata.agent_type
        )

      [:mabeam, :registry, :unregister] ->
        Debug.log("Agent unregistered",
          agent_id: metadata.agent_id,
          reason: metadata.reason
        )

      _ ->
        Debug.log("Telemetry event",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
    end

    # Here you could also send metrics to external systems like:
    # - Prometheus
    # - StatsD
    # - Custom metrics collection
  end
end
