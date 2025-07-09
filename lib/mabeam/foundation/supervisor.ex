defmodule Mabeam.Foundation.Supervisor do
  @moduledoc """
  Root supervisor for the Mabeam foundation layer.
  
  This supervisor manages all the core foundation services including:
  - Agent registry
  - Communication systems (event bus, signal bus)
  - Resource management
  - State persistence
  - Telemetry and observability
  
  The supervisor uses a proper hierarchy and restart strategies to ensure
  system resilience and proper OTP compliance.
  """
  
  use Supervisor
  require Logger
  
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl Supervisor
  def init(opts) do
    # Extract configuration
    config = Keyword.get(opts, :config, [])
    
    Logger.info("Starting Mabeam Foundation Layer")
    
    children = [
      # Core services - essential, restart always
      core_services_supervisor(config),
      
      # Communication services - restart on failure
      communication_services_supervisor(config),
      
      # Agent management services - restart on failure
      agent_services_supervisor(config),
      
      # Resource management - restart on failure
      resource_services_supervisor(config),
      
      # Observability services - can fail without affecting system
      observability_services_supervisor(config)
    ]
    
    # Use rest_for_one strategy so that if a critical service fails,
    # all dependent services are also restarted
    Supervisor.init(children, strategy: :rest_for_one)
  end
  
  ## Private Functions
  
  defp core_services_supervisor(config) do
    core_config = Keyword.get(config, :core, [])
    
    %{
      id: :core_services,
      start: {Supervisor, :start_link, [
        [
          # Phoenix PubSub for distributed communication
          pubsub_child_spec(core_config),
          
          # Agent registry
          {Mabeam.Foundation.Registry, Keyword.get(core_config, :registry, [])}
        ],
        [strategy: :one_for_one, name: Mabeam.Foundation.CoreServicesSupervisor]
      ]},
      type: :supervisor,
      restart: :permanent
    }
  end
  
  defp communication_services_supervisor(config) do
    comm_config = Keyword.get(config, :communication, [])
    
    %{
      id: :communication_services,
      start: {Supervisor, :start_link, [
        [
          # Event bus
          {Mabeam.Foundation.Communication.EventBus, Keyword.get(comm_config, :event_bus, [])},
          
          # Signal bus (to be implemented)
          # {Mabeam.Foundation.Communication.SignalBus, Keyword.get(comm_config, :signal_bus, [])},
          
          # Message router (to be implemented)
          # {Mabeam.Foundation.Communication.MessageRouter, Keyword.get(comm_config, :message_router, [])}
        ],
        [strategy: :one_for_one, name: Mabeam.Foundation.CommunicationServicesSupervisor]
      ]},
      type: :supervisor,
      restart: :permanent
    }
  end
  
  defp agent_services_supervisor(_config) do
    # agent_config = Keyword.get(config, :agent, [])
    
    %{
      id: :agent_services,
      start: {Supervisor, :start_link, [
        [
          # Dynamic supervisor for agent processes
          {DynamicSupervisor, 
           strategy: :one_for_one, 
           name: Mabeam.Foundation.AgentSupervisor,
           max_restarts: 10,
           max_seconds: 60}
        ],
        [strategy: :one_for_one, name: Mabeam.Foundation.AgentServicesSupervisor]
      ]},
      type: :supervisor,
      restart: :permanent
    }
  end
  
  defp resource_services_supervisor(_config) do
    # resource_config = Keyword.get(config, :resource, [])
    
    %{
      id: :resource_services,
      start: {Supervisor, :start_link, [
        [
          # Resource manager (to be implemented)
          # {Mabeam.Foundation.Resource.Manager, Keyword.get(resource_config, :manager, [])},
          
          # Rate limiter (to be implemented)
          # {Mabeam.Foundation.Resource.RateLimiter, Keyword.get(resource_config, :rate_limiter, [])},
          
          # Circuit breaker supervisor (to be implemented)
          # {Mabeam.Foundation.Resource.CircuitBreaker.Supervisor, Keyword.get(resource_config, :circuit_breaker, [])}
        ],
        [strategy: :rest_for_one, name: Mabeam.Foundation.ResourceServicesSupervisor]
      ]},
      type: :supervisor,
      restart: :permanent
    }
  end
  
  defp observability_services_supervisor(_config) do
    # observability_config = Keyword.get(config, :observability, [])
    
    %{
      id: :observability_services,
      start: {Supervisor, :start_link, [
        [
          # Telemetry supervisor (to be implemented)
          # {Mabeam.Foundation.Telemetry.Supervisor, Keyword.get(observability_config, :telemetry, [])},
          
          # Metrics collector (to be implemented)
          # {Mabeam.Foundation.Telemetry.Metrics.Collector, Keyword.get(observability_config, :metrics, [])},
          
          # Tracing supervisor (to be implemented)
          # {Mabeam.Foundation.Telemetry.Tracing.Supervisor, Keyword.get(observability_config, :tracing, [])}
        ],
        [strategy: :one_for_one, name: Mabeam.Foundation.ObservabilityServicesSupervisor]
      ]},
      type: :supervisor,
      restart: :temporary  # Can fail without affecting the system
    }
  end
  
  defp pubsub_child_spec(config) do
    pubsub_config = Keyword.get(config, :pubsub, [])
    
    {Phoenix.PubSub, 
     name: Mabeam.PubSub,
     adapter: Phoenix.PubSub.PG2,
     pool_size: Keyword.get(pubsub_config, :pool_size, 1)}
  end
end