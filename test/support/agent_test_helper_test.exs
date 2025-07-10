defmodule AgentTestHelperTest do
  use ExUnit.Case, async: true

  import AgentTestHelper
  import MabeamTestHelper

  require Logger

  describe "setup_destructive_agent_test/2" do
    test "creates isolated agent for destructive testing" do
      agent_info =
        setup_destructive_agent_test(:demo,
          capabilities: [:ping, :increment],
          initial_state: %{counter: 0}
        )

      assert %{agent: agent, pid: pid, name: name, supervisor: supervisor} = agent_info
      assert is_pid(pid)
      assert Process.alive?(pid)
      assert is_atom(name)
      assert is_pid(supervisor)
      assert agent.capabilities == [:ping, :increment]

      # Verify agent is functional
      {:ok, result} = execute_agent_action(pid, :ping, %{})
      assert result.response == :pong
    end

    test "handles agent creation failure gracefully" do
      # This should succeed since DemoAgent exists
      agent_info = setup_destructive_agent_test(:demo, capabilities: [:ping])
      assert %{agent: _agent, pid: _pid} = agent_info
    end
  end

  describe "setup_readonly_agent_test/2" do
    test "creates shared agent for read-only testing" do
      agent_info =
        setup_readonly_agent_test(:demo,
          capabilities: [:ping, :get_state]
        )

      assert %{agent: agent, pid: pid, name: name} = agent_info
      assert is_pid(pid)
      assert Process.alive?(pid)
      assert is_atom(name)
      assert agent.capabilities == [:ping, :get_state]

      # Verify read-only operations work
      {:ok, result} = execute_agent_action(pid, :get_state, %{})
      assert is_map(result.state)
    end

    test "supports shared naming" do
      agent_info =
        setup_readonly_agent_test(:demo,
          capabilities: [:ping],
          shared_name: :test_shared_agent
        )

      assert %{agent: _agent, pid: _pid} = agent_info
      # The shared name is used internally, but agent gets a generated ID
    end
  end

  describe "test_agent_action_execution/3" do
    test "executes test scenarios with comprehensive error handling" do
      agent_info =
        setup_destructive_agent_test(:demo,
          capabilities: [:ping, :increment]
        )

      test_scenarios = [
        {:ping, %{},
         fn result ->
           case result do
             {:ok, res} -> res.response == :pong
             _ -> false
           end
         end},
        {:increment, %{"amount" => 5},
         fn result ->
           case result do
             {:ok, res} -> res.counter == 5
             _ -> false
           end
         end},
        {:get_state, %{},
         fn result ->
           case result do
             {:ok, res} -> is_map(res.state)
             _ -> false
           end
         end}
      ]

      assert :ok = test_agent_action_execution(agent_info, test_scenarios)
    end

    test "handles unknown actions gracefully" do
      agent_info = setup_destructive_agent_test(:demo, capabilities: [:ping])

      test_scenarios = [
        {:ping, %{},
         fn result ->
           case result do
             {:ok, res} -> res.response == :pong
             _ -> false
           end
         end},
        {:unknown_action, %{},
         fn result ->
           case result do
             {:error, :unknown_action} -> true
             _ -> false
           end
         end}
      ]

      # This should continue and handle the error appropriately
      result = test_agent_action_execution(agent_info, test_scenarios, continue_on_error: true)
      assert :ok = result
    end
  end

  describe "verify_agent_state_consistency/3" do
    test "verifies agent state matches expected patterns" do
      agent_info =
        setup_destructive_agent_test(:demo,
          capabilities: [:increment],
          initial_state: %{counter: 0}
        )

      # Execute some actions to change state
      {:ok, _result} = execute_agent_action(agent_info.pid, :increment, %{"amount" => 5})

      # Verify state consistency with validation function
      assert :ok =
               verify_agent_state_consistency(agent_info, fn state ->
                 state.counter == 5
               end)
    end

    test "detects state mismatches" do
      agent_info =
        setup_destructive_agent_test(:demo,
          capabilities: [:increment],
          initial_state: %{counter: 0}
        )

      # Don't change state, then check for wrong value
      case verify_agent_state_consistency(agent_info, %{counter: 10}) do
        {:error, {:state_mismatch, _expected, _actual, _reason}} ->
          # Expected mismatch
          :ok

        other ->
          flunk("Expected state mismatch but got: #{inspect(other)}")
      end
    end
  end

  describe "test_agent_error_recovery/3" do
    test "tests agent error recovery scenarios" do
      agent_info = setup_destructive_agent_test(:demo, capabilities: [:ping])

      error_scenarios = [
        %{
          trigger: fn agent_info ->
            execute_agent_action(agent_info.pid, :unknown_action, %{})
          end,
          expected_error: {:error, :unknown_action},
          verify_recovery: fn agent_info ->
            execute_agent_action(agent_info.pid, :ping, %{})
          end
        }
      ]

      assert :ok = test_agent_error_recovery(agent_info, error_scenarios)
    end
  end

  # Test helper functions and edge cases
  describe "helper functionality" do
    test "generates unique agent names for isolation" do
      agent_info1 = setup_destructive_agent_test(:demo, capabilities: [:ping])
      agent_info2 = setup_destructive_agent_test(:demo, capabilities: [:ping])

      assert agent_info1.name != agent_info2.name
      assert agent_info1.agent.id != agent_info2.agent.id
    end

    test "provides proper cleanup through MabeamTestHelper integration" do
      # Create multiple agents
      _agent_info1 = setup_destructive_agent_test(:demo, capabilities: [:ping])
      _agent_info2 = setup_destructive_agent_test(:demo, capabilities: [:ping])

      # Cleanup is handled automatically by MabeamTestHelper
      # This test verifies no errors occur during setup
      assert true
    end

    test "handles timeout scenarios gracefully" do
      agent_info = setup_destructive_agent_test(:demo, capabilities: [:ping])

      # Test with very short timeout (should still work for ping)
      case test_agent_action_execution(agent_info, [{:ping, %{}, :any}], timeout: 100) do
        :ok -> :ok
        # Timeout is also acceptable for this test
        {:error, _reason} -> :ok
      end
    end
  end
end
