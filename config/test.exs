import Config

# Test configuration
config :logger, level: :warning

# Disable debug logging for tests
config :mabeam, Mabeam, debug: false
