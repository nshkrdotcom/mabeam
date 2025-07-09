defmodule Mabeam.Application do
  @moduledoc """
  The Mabeam application.
  
  This application starts the foundation layer and all core services
  needed for the unified agent system.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Mabeam Application")
    
    # Get application configuration
    config = Application.get_env(:mabeam, Mabeam, [])
    
    children = [
      # Start the foundation layer
      {Mabeam.Foundation.Supervisor, [config: config]},
      
      # Start telemetry
      {Mabeam.Telemetry, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mabeam.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
