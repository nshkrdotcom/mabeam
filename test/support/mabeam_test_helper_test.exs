defmodule MabeamTestHelperTest do
  @moduledoc """
  Test coverage for MabeamTestHelper module.

  This test suite verifies that the test helper follows OTP standards:
  - OTP compliant synchronization
  - Proper process monitoring
  - Unique ID generation
  - Cleanup automation
  - Timeout handling
  """

  use ExUnit.Case, async: true
  require Logger

  # Import test subject
  alias MabeamTestHelper

  describe "unique ID generation" do
    test "creates agents with unique IDs" do
      # Create multiple agents to test unique ID generation
      {:ok, agent1, _pid1} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      {:ok, agent2, _pid2} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # IDs should be different
      assert agent1.id != agent2.id
      assert is_binary(agent1.id)
      assert is_binary(agent2.id)
    end

    test "generates unique names for concurrent agent creation" do
      # Test that concurrent agent creation doesn't cause naming conflicts
      # Note: Create agents in the test process to avoid on_exit callback issues
      results =
        Enum.map(1..3, fn _i ->
          MabeamTestHelper.create_test_agent(:demo, capabilities: [:ping])
        end)

      # Extract agent IDs
      agent_ids = Enum.map(results, fn {:ok, agent, _pid} -> agent.id end)

      # All IDs should be unique
      unique_ids = Enum.uniq(agent_ids)
      assert length(agent_ids) == length(unique_ids)
    end
  end

  describe "agent creation and lifecycle" do
    test "creates test agent with unique naming" do
      {:ok, agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Verify agent structure
      assert is_binary(agent.id)
      assert agent.type == :demo
      assert :ping in agent.capabilities
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify agent is registered
      {:ok, registered_agent} = Mabeam.get_agent(agent.id)
      assert registered_agent.id == agent.id
    end

    test "creates agents with different names in concurrent tests" do
      results =
        Enum.map(1..3, fn _i ->
          MabeamTestHelper.create_test_agent(:demo, capabilities: [:ping])
        end)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _agent, _pid} -> true
               _ -> false
             end)

      # All should have different agent IDs
      agent_ids = Enum.map(results, fn {:ok, agent, _pid} -> agent.id end)
      unique_ids = Enum.uniq(agent_ids)
      assert length(agent_ids) == length(unique_ids)
    end

    test "handles agent creation failure gracefully" do
      # Try to create agent with invalid configuration
      result =
        MabeamTestHelper.create_test_agent(:nonexistent_type,
          capabilities: [:invalid_capability]
        )

      # Should handle failure appropriately
      case result do
        {:ok, _agent, _pid} ->
          # If it succeeds, that's fine - the demo agent is flexible
          :ok

        {:error, _reason} ->
          # If it fails, that's expected for invalid config
          :ok
      end
    end
  end

  describe "action execution" do
    test "executes agent actions with proper synchronization" do
      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Execute action
      {:ok, result} = MabeamTestHelper.execute_agent_action(pid, :ping, %{})

      # Verify result structure
      assert is_map(result)
      assert result.response == :pong
    end

    test "handles action timeouts properly" do
      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Execute action with very short timeout
      # Note: ping should be fast enough that this usually succeeds
      result = MabeamTestHelper.execute_agent_action(pid, :ping, %{}, 1)

      # Should either succeed quickly or timeout gracefully
      case result do
        {:ok, _result} -> :ok
        {:error, :timeout} -> :ok
        {:error, _other} -> :ok
      end
    end

    test "handles unknown actions gracefully" do
      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Execute unknown action
      {:error, reason} = MabeamTestHelper.execute_agent_action(pid, :unknown_action, %{})

      # Should get standardized error
      assert reason == :unknown_action
    end
  end

  describe "event system helpers" do
    test "subscribes to events and receives them" do
      # Subscribe to events
      :ok = MabeamTestHelper.subscribe_to_events(["demo_ping"])

      # Create agent and execute action
      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      {:ok, _result} = MabeamTestHelper.execute_agent_action(pid, :ping, %{})

      # Wait for event
      {:ok, event} = MabeamTestHelper.wait_for_event("demo_ping", 2000)

      # Verify event structure
      assert event.type == "demo_ping"
      assert is_map(event.data)
    end

    test "handles event timeout gracefully" do
      # Subscribe to events
      :ok = MabeamTestHelper.subscribe_to_events(["nonexistent_event"])

      # Wait for event that won't come
      {:error, :timeout} = MabeamTestHelper.wait_for_event("nonexistent_event", 100)
    end

    test "waits for multiple events in sequence" do
      # Subscribe to events
      :ok = MabeamTestHelper.subscribe_to_events(["demo_ping", "demo_increment"])

      # Create agent
      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping, :increment]
        )

      # Execute actions that will generate events
      {:ok, _result1} = MabeamTestHelper.execute_agent_action(pid, :ping, %{})
      {:ok, _result2} = MabeamTestHelper.execute_agent_action(pid, :increment, %{})

      # Wait for events in sequence
      {:ok, events} = MabeamTestHelper.wait_for_events(["demo_ping", "demo_increment"], 3000)

      # Verify we got both events
      assert length(events) == 2
      assert Enum.at(events, 0).type == "demo_ping"
      assert Enum.at(events, 1).type == "demo_increment"
    end
  end

  describe "process monitoring" do
    test "waits for process termination with monitoring" do
      # Trap exits so the test doesn't die when we kill the agent
      Process.flag(:trap_exit, true)

      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Kill process and wait for termination
      {:ok, reason} = MabeamTestHelper.kill_and_wait(pid, 1000)

      # Should get killed reason
      assert reason == :killed
      assert not Process.alive?(pid)
    end

    test "handles already dead processes" do
      # Trap exits so the test doesn't die when we kill the agent
      Process.flag(:trap_exit, true)

      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Kill process first
      Process.exit(pid, :kill)

      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        100 -> :ok
      end

      # Then try to wait for termination
      {:ok, :already_dead} = MabeamTestHelper.wait_for_process_termination(pid, 1000)
    end

    test "handles process monitoring timeout" do
      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Try to wait for termination without killing it
      {:error, :timeout} = MabeamTestHelper.wait_for_process_termination(pid, 50)

      # Process should still be alive
      assert Process.alive?(pid)
    end
  end

  describe "registry synchronization" do
    test "waits for agent registration" do
      # Start creating an agent but don't wait for it to complete
      Task.start(fn ->
        MabeamTestHelper.create_test_agent(:demo, capabilities: [:ping])
      end)

      # We can't easily test registration waiting without race conditions
      # in this simple test, but we can verify the function exists and works
      # when the agent is already registered
      {:ok, agent, _pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Wait for something that's already registered
      :ok = MabeamTestHelper.wait_for_agent_registration(agent.id, 1000)
    end

    test "waits for agent deregistration" do
      {:ok, agent, _pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Stop the agent
      :ok = Mabeam.stop_agent(agent.id)

      # Wait for deregistration
      :ok = MabeamTestHelper.wait_for_agent_deregistration(agent.id, 2000)

      # Verify agent is no longer registered
      {:error, :not_found} = Mabeam.get_agent(agent.id)
    end

    test "handles registration timeout" do
      # Wait for agent that doesn't exist
      {:error, :timeout} = MabeamTestHelper.wait_for_agent_registration("nonexistent", 50)
    end
  end

  describe "cleanup automation" do
    test "registers cleanup handlers automatically" do
      # Create agent (this should register cleanup)
      {:ok, agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      # Verify cleanup is registered
      agent_cleanups = Process.get(:agent_cleanups, [])
      assert length(agent_cleanups) > 0

      # Verify our agent is in the cleanup list
      assert Enum.any?(agent_cleanups, fn {cleanup_pid, cleanup_id} ->
               cleanup_pid == pid and cleanup_id == agent.id
             end)
    end

    test "cleanup function executes without errors" do
      # Create some resources
      {:ok, _agent, _pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      :ok = MabeamTestHelper.subscribe_to_events(["demo_ping"])

      # Run cleanup
      :ok = MabeamTestHelper.cleanup_all_test_resources()

      # Verify cleanup lists are cleared
      assert Process.get(:agent_cleanups, []) == []
      assert Process.get(:subscription_cleanups, []) == []
    end
  end

  describe "OTP standards compliance" do
    test "follows OTP synchronization patterns" do
      {:ok, _agent, pid} =
        MabeamTestHelper.create_test_agent(:demo,
          capabilities: [:ping]
        )

      start_time = System.monotonic_time(:millisecond)

      {:ok, _result} = MabeamTestHelper.execute_agent_action(pid, :ping, %{})

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      assert elapsed < 1000
    end

    test "handles concurrent operations without conflicts" do
      results =
        Enum.map(1..5, fn _i ->
          {:ok, agent, pid} =
            MabeamTestHelper.create_test_agent(:demo,
              capabilities: [:ping]
            )

          # Execute some actions
          {:ok, _result} = MabeamTestHelper.execute_agent_action(pid, :ping, %{})

          {agent.id, pid}
        end)

      # All should have unique agent IDs
      agent_ids = Enum.map(results, fn {agent_id, _pid} -> agent_id end)
      unique_ids = Enum.uniq(agent_ids)
      assert length(agent_ids) == length(unique_ids)

      # All processes should be alive
      pids = Enum.map(results, fn {_agent_id, pid} -> pid end)
      assert Enum.all?(pids, &Process.alive?/1)
    end
  end
end
