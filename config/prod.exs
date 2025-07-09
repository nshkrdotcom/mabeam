import Config

# Production configuration
config :logger, level: :info

# Disable debug logging for production
config :mabeam, Mabeam,
  debug: false