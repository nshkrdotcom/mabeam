import Config

# General application configuration
config :mabeam, Mabeam,
  # Foundation configuration
  foundation: [
    # Registry configuration
    registry: [
      cleanup_interval: 60_000,
      max_cleanup_batch_size: 100
    ],
    
    # Event bus configuration
    event_bus: [
      max_subscribers: 1000,
      default_timeout: 5000
    ],
    
    # Telemetry configuration
    telemetry: [
      enabled: true,
      metrics_interval: 30_000
    ]
  ]

# Import environment specific config
import_config "#{Mix.env()}.exs"