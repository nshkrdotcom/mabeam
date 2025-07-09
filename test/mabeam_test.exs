defmodule MabeamTest do
  use ExUnit.Case
  doctest Mabeam
  
  alias Mabeam.DemoAgent

  test "system starts successfully" do
    # The system should start automatically with the application
    # Just verify that key services are available
    assert Process.whereis(Mabeam.Foundation.Registry) != nil
    assert Process.whereis(Mabeam.Foundation.Communication.EventBus) != nil
  end
  
  test "can start and manage agents" do
    # Test basic agent lifecycle
    {:ok, agent, pid} = DemoAgent.start_link(type: :test, capabilities: [:ping])
    
    # Should be able to find the agent
    {:ok, found_agent} = Mabeam.get_agent(agent.id)
    assert found_agent.id == agent.id
    assert found_agent.type == :test
    
    # Should be able to get the process
    {:ok, found_pid} = Mabeam.get_agent_process(agent.id)
    assert found_pid == pid
    
    # Should be able to stop the agent
    :ok = Mabeam.stop_agent(agent.id)
    
    # Should no longer be findable
    assert {:error, :not_found} = Mabeam.get_agent(agent.id)
  end
  
  test "can list agents by type and capability" do
    # Start multiple agents
    {:ok, agent1, _pid1} = DemoAgent.start_link(type: :type1, capabilities: [:ping, :increment])
    {:ok, agent2, _pid2} = DemoAgent.start_link(type: :type2, capabilities: [:ping, :add_message])
    {:ok, agent3, _pid3} = DemoAgent.start_link(type: :type1, capabilities: [:increment, :get_state])
    
    # Test listing by type
    type1_agents = Mabeam.list_agents_by_type(:type1)
    assert length(type1_agents) == 2
    
    type2_agents = Mabeam.list_agents_by_type(:type2)
    assert length(type2_agents) == 1
    
    # Test listing by capability
    ping_agents = Mabeam.list_agents_by_capability(:ping)
    assert length(ping_agents) == 2
    
    increment_agents = Mabeam.list_agents_by_capability(:increment)
    assert length(increment_agents) == 2
    
    # Clean up
    :ok = Mabeam.stop_agent(agent1.id)
    :ok = Mabeam.stop_agent(agent2.id)
    :ok = Mabeam.stop_agent(agent3.id)
  end
  
  test "event system works correctly" do
    # Subscribe to events
    Mabeam.subscribe(:test_event)
    
    # Emit an event
    {:ok, event_id} = Mabeam.emit_event(:test_event, %{data: "test"}, %{source: "test"})
    
    # Should receive the event
    assert_receive {:event, event}
    assert event.type == :test_event
    assert event.data == %{data: "test"}
    assert event.metadata == %{source: "test"}
    assert is_binary(event_id)
    
    # Test pattern subscription
    Mabeam.subscribe_pattern("test.*")
    
    {:ok, _event_id} = Mabeam.emit_event(:test_pattern, %{data: "pattern"})
    
    # Should receive the pattern event
    assert_receive {:event, event}
    assert event.type == :test_pattern
    assert event.data == %{data: "pattern"}
  end
  
  test "can retrieve event history" do
    # Emit some events
    {:ok, _id1} = Mabeam.emit_event(:history_event_1, %{data: "first"})
    {:ok, _id2} = Mabeam.emit_event(:history_event_2, %{data: "second"})
    
    # Get history
    history = Mabeam.get_event_history(10)
    
    # Should contain our events
    assert length(history) >= 2
    
    # Find our events in the history
    our_events = Enum.filter(history, fn event ->
      event.type in [:history_event_1, :history_event_2]
    end)
    
    assert length(our_events) >= 2
  end
end
