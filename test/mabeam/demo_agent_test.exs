defmodule Mabeam.DemoAgentTest do
  use ExUnit.Case
  alias Mabeam.DemoAgent
  
  # Helper function to receive events for a specific agent, filtering out events from other agents
  defp receive_event_for_agent(agent_id, event_type, timeout) do
    receive do
      {:event, event} ->
        if event.type == event_type and event.data.agent_id == agent_id do
          event
        else
          # This event is from another agent or wrong type, ignore and try again
          receive_event_for_agent(agent_id, event_type, timeout)
        end
    after
      timeout ->
        flunk("Did not receive #{event_type} event for agent #{agent_id} within #{timeout}ms")
    end
  end
  
  describe "DemoAgent functionality" do
    test "starts and responds to ping" do
      # Start the demo agent
      {:ok, agent, pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:ping, :increment, :get_state, :add_message, :get_messages, :clear_messages],
        initial_state: %{counter: 0, messages: []}
      )
      
      # Test ping action
      {:ok, result} = DemoAgent.execute_action(pid, :ping, %{})
      
      assert result.response == :pong
      assert result.agent_id == agent.id
      assert %DateTime{} = result.timestamp
      assert result.counter == 0
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "handles increment action" do
      {:ok, agent, pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:increment],
        initial_state: %{counter: 0, messages: []}
      )
      
      # Test increment without amount (should default to 1)
      {:ok, result1} = DemoAgent.execute_action(pid, :increment, %{})
      assert result1.counter == 1
      assert result1.incremented_by == 1
      
      # Test increment with specific amount
      {:ok, result2} = DemoAgent.execute_action(pid, :increment, %{"amount" => 5})
      assert result2.counter == 6
      assert result2.incremented_by == 5
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "handles message operations" do
      {:ok, agent, pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:add_message, :get_messages, :clear_messages],
        initial_state: %{counter: 0, messages: []}
      )
      
      # Add a message
      {:ok, result1} = DemoAgent.execute_action(pid, :add_message, %{"message" => "Hello, World!"})
      assert is_binary(result1.message_id)
      assert result1.total_messages == 1
      
      # Get messages
      {:ok, result2} = DemoAgent.execute_action(pid, :get_messages, %{})
      assert result2.count == 1
      assert length(result2.messages) == 1
      assert hd(result2.messages).content == "Hello, World!"
      
      # Add another message
      {:ok, result3} = DemoAgent.execute_action(pid, :add_message, %{"message" => "Second message"})
      assert result3.total_messages == 2
      
      # Clear messages
      {:ok, result4} = DemoAgent.execute_action(pid, :clear_messages, %{})
      assert result4.cleared_count == 2
      
      # Verify messages are cleared
      {:ok, result5} = DemoAgent.execute_action(pid, :get_messages, %{})
      assert result5.count == 0
      assert result5.messages == []
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "handles get_state action" do
      {:ok, agent, pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:get_state],
        initial_state: %{counter: 42, messages: []}
      )
      
      {:ok, result} = DemoAgent.execute_action(pid, :get_state, %{})
      
      assert result.state.counter == 42
      assert result.state.messages == []
      assert result.lifecycle == :ready
      assert result.capabilities == [:get_state]
      assert result.type == :demo
      assert %DateTime{} = result.created_at
      assert %DateTime{} = result.updated_at
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "handles error simulation" do
      {:ok, agent, pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:simulate_error],
        initial_state: %{counter: 0, messages: []}
      )
      
      # Test error simulation
      {:error, result} = DemoAgent.execute_action(pid, :simulate_error, %{})
      assert result == :simulated_error
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "handles unknown actions" do
      {:ok, agent, pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [],
        initial_state: %{counter: 0, messages: []}
      )
      
      # Test unknown action
      {:error, result} = DemoAgent.execute_action(pid, :unknown_action, %{})
      assert result == {:unknown_action, :unknown_action}
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "emits events during operations" do
      # Subscribe to demo events
      Mabeam.subscribe_pattern("demo.*")
      
      {:ok, agent, pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:ping, :increment, :add_message],
        initial_state: %{counter: 0, messages: []}
      )
      
      # Test ping - should emit demo_ping event
      {:ok, _result} = DemoAgent.execute_action(pid, :ping, %{})
      
      # Wait for the specific demo_ping event (ignore other events)
      receive do
        {:event, %{type: :demo_ping} = event} ->
          assert event.type == :demo_ping
          assert event.data.agent_id == agent.id
        {:event, _other_event} ->
          # If we get a different event, wait for the ping event
          receive do
            {:event, %{type: :demo_ping} = event} ->
              assert event.type == :demo_ping
              assert event.data.agent_id == agent.id
          after
            1000 -> flunk("Did not receive demo_ping event")
          end
      after
        1000 -> flunk("Did not receive any event")
      end
      
      # Test increment - should emit demo_increment event
      {:ok, _result} = DemoAgent.execute_action(pid, :increment, %{"amount" => 3})
      
      # Wait for the specific demo_increment event (ignore other events)
      increment_event = receive do
        {:event, %{type: :demo_increment} = event} ->
          assert event.type == :demo_increment
          assert event.data.agent_id == agent.id
          event
        {:event, _other_event} ->
          # If we get a different event, wait for the increment event
          receive do
            {:event, %{type: :demo_increment} = event} ->
              assert event.type == :demo_increment
              assert event.data.agent_id == agent.id
              event
          after
            1000 -> flunk("Did not receive demo_increment event")
          end
      after
        1000 -> flunk("Did not receive any event")
      end
      assert increment_event.data.amount == 3
      
      # Test add message - should emit demo_message_added event
      {:ok, _result} = DemoAgent.execute_action(pid, :add_message, %{"message" => "Test"})
      
      # Wait for the specific demo_message_added event (ignore other events)
      message_event = receive do
        {:event, %{type: :demo_message_added} = event} ->
          assert event.type == :demo_message_added
          assert event.data.agent_id == agent.id
          event
        {:event, _other_event} ->
          # If we get a different event, wait for the message_added event
          receive do
            {:event, %{type: :demo_message_added} = event} ->
              assert event.type == :demo_message_added
              assert event.data.agent_id == agent.id
              event
          after
            1000 -> flunk("Did not receive demo_message_added event")
          end
      after
        1000 -> flunk("Did not receive any event")
      end
      assert message_event.data.message.content == "Test"
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "can be found in registry" do
      {:ok, agent, _pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:ping]
      )
      
      # Should be findable by ID
      {:ok, found_agent} = Mabeam.get_agent(agent.id)
      assert found_agent.id == agent.id
      assert found_agent.type == :demo
      
      # Should be findable by type
      demo_agents = Mabeam.list_agents_by_type(:demo)
      assert length(demo_agents) >= 1
      assert Enum.any?(demo_agents, fn a -> a.id == agent.id end)
      
      # Should be findable by capability
      ping_agents = Mabeam.list_agents_by_capability(:ping)
      assert length(ping_agents) >= 1
      assert Enum.any?(ping_agents, fn a -> a.id == agent.id end)
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
    
    test "handles system events" do
      # Subscribe to demo status responses
      Mabeam.subscribe(:demo_status_response)
      
      {:ok, agent, _pid} = DemoAgent.start_link(
        type: :demo,
        capabilities: [:ping],
        initial_state: %{counter: 5, messages: []}
      )
      
      # Emit system status event
      {:ok, _event_id} = Mabeam.emit_event(:system_status, %{requester: "test"})
      
      # Should receive status response - filter by agent ID to handle concurrent tests
      event = receive_event_for_agent(agent.id, :demo_status_response, 5000)
      assert event.type == :demo_status_response
      assert event.data.agent_id == agent.id
      assert event.data.status == :healthy
      assert event.data.counter == 5
      
      # Clean up
      :ok = Mabeam.stop_agent(agent.id)
    end
  end
end