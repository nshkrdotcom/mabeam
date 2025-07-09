# MABEAM Quick Reference

## Core API

### Agent Management
```elixir
# Start agent
{:ok, agent, pid} = Mabeam.start_agent(Module, opts)

# Stop agent
:ok = Mabeam.stop_agent(agent_id)

# Restart agent
{:ok, agent, pid} = Mabeam.restart_agent(agent_id)

# Get agent info
{:ok, agent} = Mabeam.get_agent(agent_id)

# List agents
agents = Mabeam.list_agents()
agents = Mabeam.list_agents_by_type(:demo)
agents = Mabeam.list_agents_by_capability(:ping)
```

### Action Execution
```elixir
# Execute action
{:ok, result} = Mabeam.execute_action(agent_id, :action_name, params)

# With DemoAgent
{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :ping, %{})
```

### Event System
```elixir
# Emit event
{:ok, event_id} = Mabeam.emit_event(:event_type, data)

# Subscribe
:ok = Mabeam.subscribe(:event_type)
:ok = Mabeam.subscribe_pattern("pattern.*")

# Unsubscribe
:ok = Mabeam.unsubscribe(:event_type)
:ok = Mabeam.unsubscribe_pattern("pattern.*")

# Get history
events = Mabeam.get_event_history(limit)
```

## Agent Implementation

### Basic Agent
```elixir
defmodule MyAgent do
  use Mabeam.Agent

  @impl true
  def init(agent, _config) do
    {:ok, %{agent | state: %{data: "initial"}}}
  end

  @impl true
  def handle_action(agent, :my_action, params) do
    # Process action and update state
    updated_agent = %{agent | state: new_state}
    {:ok, updated_agent, result}
  end

  @impl true
  def handle_event(agent, event) do
    # Handle incoming event
    {:ok, updated_agent}
  end
end
```

### Agent Structure
```elixir
%Agent{
  id: "agent_uuid",
  type: :agent_type,
  state: %{},
  capabilities: [:action1, :action2],
  lifecycle: :ready,
  metadata: %{},
  created_at: ~U[...],
  updated_at: ~U[...]
}
```

## Demo Agent Actions

```elixir
# Start demo agent
{:ok, agent, pid} = Mabeam.DemoAgent.start_link(
  type: :demo,
  capabilities: [:ping, :increment, :get_state],
  initial_state: %{counter: 0, messages: []}
)

# Available actions
{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :ping, %{})
{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :increment, %{amount: 5})
{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :get_state, %{})
{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :add_message, %{message: "Hello"})
{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :get_messages, %{})
{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :clear_messages, %{})
{:error, reason} = Mabeam.DemoAgent.execute_action(pid, :simulate_error, %{})
```

## Event Types

### Demo Agent Events
- `:demo_ping` - Ping action executed
- `:demo_increment` - Increment action executed  
- `:demo_message_added` - Message added to agent
- `:demo_status_response` - Response to system status

### System Events
- `:system_status` - System status check
- `:agent_lifecycle.*` - Agent lifecycle events

## Testing Patterns

### Basic Test
```elixir
test "agent functionality" do
  {:ok, agent, pid} = Mabeam.DemoAgent.start_link(
    type: :demo,
    capabilities: [:ping]
  )
  
  {:ok, result} = Mabeam.DemoAgent.execute_action(pid, :ping, %{})
  assert result.response == :pong
  
  Mabeam.stop_agent(agent.id)
end
```

### Event Testing
```elixir
test "event handling" do
  Mabeam.subscribe(:demo_ping)
  
  {:ok, agent, pid} = Mabeam.DemoAgent.start_link(
    type: :demo,
    capabilities: [:ping]
  )
  
  {:ok, _result} = Mabeam.DemoAgent.execute_action(pid, :ping, %{})
  
  # Filter events by agent ID for concurrent tests
  event = receive_event_for_agent(agent.id, :demo_ping, 5000)
  assert event.data.agent_id == agent.id
  
  Mabeam.stop_agent(agent.id)
end

# Helper function for concurrent test safety
defp receive_event_for_agent(agent_id, event_type, timeout) do
  receive do
    {:event, event} ->
      if event.type == event_type and event.data.agent_id == agent_id do
        event
      else
        receive_event_for_agent(agent_id, event_type, timeout)
      end
  after
    timeout -> flunk("Did not receive event within timeout")
  end
end
```

### Concurrent Test Safety
```elixir
# Use Task.async to avoid process linking
{:ok, agent, pid} = Task.async(fn -> 
  Mabeam.DemoAgent.start_link(
    type: :demo,
    capabilities: [:ping]
  )
end) |> Task.await()
```

## Common Patterns

### Multi-Agent Coordination
```elixir
# Start multiple agents
agents = Enum.map(1..3, fn _i ->
  {:ok, agent, pid} = Mabeam.start_agent(MyAgent, type: :worker)
  {agent, pid}
end)

# Subscribe to events
Mabeam.subscribe_pattern("worker.*")

# Execute actions on all agents
Enum.each(agents, fn {agent, _pid} ->
  Mabeam.execute_action(agent.id, :work, %{task: "process"})
end)

# Collect results
results = Enum.map(1..3, fn _ ->
  receive do
    {:event, event} -> event
  after
    5000 -> nil
  end
end)
```

### Error Handling
```elixir
case Mabeam.execute_action(agent_id, :risky_action, params) do
  {:ok, result} ->
    # Success
    IO.puts("Action succeeded: #{inspect(result)}")
    
  {:error, reason} ->
    # Error
    IO.puts("Action failed: #{inspect(reason)}")
end
```

## Type System

### IDs
```elixir
# Generate typed IDs
agent_id = Mabeam.Types.ID.agent_id()
event_id = Mabeam.Types.ID.event_id()

# Extract raw values
raw_id = Mabeam.Types.ID.unwrap(agent_id)

# Type checking
Mabeam.Types.ID.is_type?(agent_id, :agent) # true
```

### Event Structure
```elixir
%Mabeam.Types.Communication.Event{
  id: "event_uuid",
  type: :event_type,
  source: #PID<0.123.0>,
  data: %{key: "value"},
  metadata: %{},
  timestamp: ~U[2025-01-09 11:30:00.000000Z]
}
```

## Performance Tips

1. **Use specific event subscriptions** instead of broad patterns
2. **Keep agent state minimal** and efficient
3. **Batch operations** when possible
4. **Monitor process count** and memory usage
5. **Use proper cleanup** in tests and production

## Debugging

### Enable Debug Logging
```elixir
# In config/config.exs
config :logger, level: :debug

# Or at runtime
Logger.configure(level: :debug)
```

### System Monitoring
```elixir
# Check agent count
agents = Mabeam.list_agents()
IO.puts("Total agents: #{length(agents)}")

# Check event history
events = Mabeam.get_event_history(10)
IO.puts("Recent events: #{length(events)}")

# Process monitoring
process_count = length(Process.list())
IO.puts("Total processes: #{process_count}")
```

## File Structure

```
lib/mabeam/
├── mabeam.ex                         # Main API
├── agent.ex                           # Agent behaviour
├── demo_agent.ex                      # Demo implementation
├── types/
│   ├── id.ex                         # ID system
│   ├── agent.ex                      # Agent types
│   └── communication.ex              # Communication types
└── foundation/
    ├── supervisor.ex                 # Supervision tree
    ├── registry.ex                   # Agent registry
    ├── agent/
    │   ├── lifecycle.ex              # Lifecycle management
    │   └── server.ex                 # Agent server
    └── communication/
        └── event_bus.ex              # Event system
```

---

**Quick Start**: `{:ok, agent, pid} = Mabeam.DemoAgent.start_link(type: :demo, capabilities: [:ping])`  
**Execute Action**: `{:ok, result} = Mabeam.DemoAgent.execute_action(pid, :ping, %{})`  
**Subscribe to Events**: `Mabeam.subscribe(:demo_ping)`  
**Stop Agent**: `Mabeam.stop_agent(agent.id)`