defmodule MabeamIntegrationTest do
  use ExUnit.Case
  alias Mabeam.DemoAgent

  describe "Mabeam system integration" do
    test "complete system lifecycle" do
      # Start multiple agents (use Task.async to avoid linking to test process)
      {:ok, agent1, pid1} =
        Task.async(fn ->
          DemoAgent.start_link(
            type: :demo,
            capabilities: [:ping, :increment, :get_state]
          )
        end)
        |> Task.await()

      {:ok, agent2, pid2} =
        Task.async(fn ->
          DemoAgent.start_link(
            type: :demo,
            capabilities: [:ping, :add_message, :get_messages]
          )
        end)
        |> Task.await()

      # Test that both agents are in the registry
      agents = Mabeam.list_agents()
      assert length(agents) >= 2

      demo_agents = Mabeam.list_agents_by_type(:demo)
      assert length(demo_agents) >= 2

      # Test cross-agent communication via events
      Mabeam.subscribe_pattern("demo.*")

      # Execute actions on both agents
      {:ok, result1} = DemoAgent.execute_action(pid1, :ping, %{})
      assert result1.response == :pong

      {:ok, result2} =
        DemoAgent.execute_action(pid2, :add_message, %{"message" => "Hello from agent 2"})

      assert result2.total_messages == 1

      # Should have received events from both agents
      assert_receive {:event, event}
      assert event.type == "demo_ping"
      assert event.data.agent_id == agent1.id

      assert_receive {:event, event}
      assert event.type == "demo_message_added"
      assert event.data.agent_id == agent2.id

      # Test agent coordination
      {:ok, _result} = DemoAgent.execute_action(pid1, :increment, %{"amount" => 3})
      assert_receive {:event, event}
      assert event.type == "demo_increment"
      assert event.data.amount == 3

      # Test system-wide events
      Mabeam.subscribe("demo_status_response")

      Mabeam.list_agents()

      {:ok, _event_id} = Mabeam.emit_event("system_status", %{requester: "integration_test"})

      # Should receive responses from both agents
      assert_receive {:event, event}
      assert event.type == "demo_status_response"
      assert event.data.status == :healthy

      assert_receive {:event, event}
      assert event.type == "demo_status_response"
      assert event.data.status == :healthy

      # Test agent restart
      original_agent1 = agent1
      {:ok, restarted_agent1, restarted_pid1} = Mabeam.restart_agent(agent1.id)

      # Should have same ID but different process
      assert restarted_agent1.id == original_agent1.id
      assert restarted_pid1 != pid1

      # Test graceful shutdown
      :ok = Mabeam.stop_agent(agent1.id)
      :ok = Mabeam.stop_agent(agent2.id)

      # Agents should be removed from registry
      Mabeam.list_agents()

      assert {:error, :not_found} = Mabeam.get_agent(agent1.id)
      assert {:error, :not_found} = Mabeam.get_agent(agent2.id)
    end

    test "system resilience and fault tolerance" do
      # Start an agent (use Task.async to avoid linking to test process)
      {:ok, agent, pid} =
        Task.async(fn ->
          DemoAgent.start_link(
            type: :demo,
            capabilities: [:ping, :simulate_error]
          )
        end)
        |> Task.await()

      # Test that system handles errors gracefully
      {:error, error_result} = DemoAgent.execute_action(pid, :simulate_error, %{})
      assert error_result == :simulated_error

      # Agent should still be responsive after error
      {:ok, ping_result} = DemoAgent.execute_action(pid, :ping, %{})
      assert ping_result.response == :pong

      # Test that killing an agent process doesn't crash the system
      Process.exit(pid, :kill)

      # Use GenServer call to ensure registry cleanup is processed
      Mabeam.list_agents()  # This synchronizes with registry

      # Agent should be removed from registry
      assert {:error, :not_found} = Mabeam.get_agent(agent.id)

      # System should still be functional
      {:ok, new_agent, _new_pid} =
        Task.async(fn ->
          DemoAgent.start_link(type: :demo, capabilities: [:ping])
        end)
        |> Task.await()

      # Clean up
      :ok = Mabeam.stop_agent(new_agent.id)
    end

    test "event system scalability" do
      # Subscribe to all demo events
      Mabeam.subscribe_pattern("demo.*")

      # Start multiple agents (use Task.async to avoid linking to test process)
      agents =
        Enum.map(1..3, fn _i ->
          {:ok, agent, pid} =
            Task.async(fn ->
              DemoAgent.start_link(
                type: :demo,
                capabilities: [:ping, :increment]
              )
            end)
            |> Task.await()

          {agent, pid}
        end)

      # Execute actions on all agents simultaneously
      Enum.each(agents, fn {_agent, pid} ->
        spawn(fn ->
          {:ok, _result} = DemoAgent.execute_action(pid, :ping, %{})
          {:ok, _result} = DemoAgent.execute_action(pid, :increment, %{"amount" => 1})
        end)
      end)

      # Should receive events from all agents (6 events total: 3 ping + 3 increment)
      # Since actions are executed in parallel, events may arrive in any order
      all_events =
        Enum.map(1..6, fn _ ->
          assert_receive {:event, event}
          event
        end)

      # Group events by type
      ping_events = Enum.filter(all_events, &(&1.type == "demo_ping"))
      increment_events = Enum.filter(all_events, &(&1.type == "demo_increment"))

      # Should have received exactly 3 ping events and 3 increment events
      assert length(ping_events) == 3
      assert length(increment_events) == 3

      # All agents should have emitted events
      ping_agent_ids = Enum.map(ping_events, & &1.data.agent_id)
      increment_agent_ids = Enum.map(increment_events, & &1.data.agent_id)

      assert length(Enum.uniq(ping_agent_ids)) == 3
      assert length(Enum.uniq(increment_agent_ids)) == 3

      # Clean up
      Enum.each(agents, fn {agent, _pid} ->
        :ok = Mabeam.stop_agent(agent.id)
      end)
    end

    test "registry consistency under load" do
      # Start many agents quickly (use Task.async to avoid linking to test process)
      agents =
        Enum.map(1..10, fn _i ->
          {:ok, agent, pid} =
            Task.async(fn ->
              DemoAgent.start_link(
                type: :load_test,
                capabilities: [:ping]
              )
            end)
            |> Task.await()

          {agent, pid}
        end)

      # All agents should be in registry
      load_test_agents = Mabeam.list_agents_by_type(:load_test)

      assert length(load_test_agents) == 10

      # Stop half of them
      {to_stop, to_keep} = Enum.split(agents, 5)

      Enum.each(to_stop, fn {agent, _pid} ->
        :ok = Mabeam.stop_agent(agent.id)
      end)

      Mabeam.list_agents()

      # Registry should be consistent
      remaining_agents = Mabeam.list_agents_by_type(:load_test)
      assert length(remaining_agents) == 5

      # Verify the right agents remain
      remaining_ids = Enum.map(remaining_agents, & &1.id)
      expected_ids = Enum.map(to_keep, fn {agent, _pid} -> agent.id end)

      assert Enum.sort(remaining_ids) == Enum.sort(expected_ids)

      # Clean up remaining agents
      Enum.each(to_keep, fn {agent, _pid} ->
        :ok = Mabeam.stop_agent(agent.id)
      end)
    end

    test "event history and pattern matching" do
      # Emit various events
      {:ok, _id1} = Mabeam.emit_event("test_event_1", %{data: "first"})
      {:ok, _id2} = Mabeam.emit_event("test_event_2", %{data: "second"})
      {:ok, _id3} = Mabeam.emit_event("other_event", %{data: "third"})

      # Get history
      history = Mabeam.get_event_history(10)
      assert length(history) >= 3

      # Test pattern subscription
      Mabeam.subscribe_pattern("test.*")

      {:ok, _id4} = Mabeam.emit_event("test_event_3", %{data: "fourth"})
      {:ok, _id5} = Mabeam.emit_event("other_event_2", %{data: "fifth"})

      # Should only receive test events
      assert_receive {:event, event}
      assert event.type == "test_event_3"
      assert event.data.data == "fourth"

      # Should not receive other events
      refute_receive {:event, %{type: :other_event_2}}
    end
  end
end
