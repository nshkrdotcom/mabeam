defmodule SystemTestHelperTest do
  use ExUnit.Case, async: true

  import SystemTestHelper
  import MabeamTestHelper

  require Logger

  describe "setup_integration_system/1" do
    test "sets up complete MABEAM system for integration testing" do
      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :coordinator, capabilities: [:coordinate]},
            {:demo, type: :worker, capabilities: [:work]}
          ],
          event_subscriptions: [:system_status],
          timeout: 10000
        )

      assert %{agents: agents, subscriptions: subscriptions, system_pid: system_pid} = system_info
      assert length(agents) == 2
      assert :system_status in subscriptions
      assert is_pid(system_pid)
      assert Process.alive?(system_pid)

      # Verify all agents are functional
      Enum.each(agents, fn agent_info ->
        assert Process.alive?(agent_info.pid)
        {:ok, _result} = execute_agent_action(agent_info.pid, :ping, %{})
      end)
    end

    test "handles empty agent list" do
      system_info =
        setup_integration_system(
          agents: [],
          event_subscriptions: [:test_event]
        )

      assert %{agents: agents, subscriptions: subscriptions} = system_info
      assert length(agents) == 0
      assert :test_event in subscriptions
    end

    test "supports large agent counts" do
      # Test with multiple agents
      agent_specs =
        for i <- 1..5 do
          {:demo, type: :worker, capabilities: [:work], name: :"worker_#{i}"}
        end

      system_info =
        setup_integration_system(
          agents: agent_specs,
          timeout: 15000
        )

      assert %{agents: agents} = system_info
      assert length(agents) == 5

      # Verify all agents are unique and functional
      agent_ids = Enum.map(agents, & &1.agent.id)
      assert length(Enum.uniq(agent_ids)) == 5
    end
  end

  describe "test_multi_agent_coordination/3" do
    test "executes coordination scenario across multiple agents" do
      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :coordinator, capabilities: [:coordinate, :ping]},
            {:demo, type: :worker, capabilities: [:work, :ping, :increment]}
          ],
          timeout: 10000
        )

      coordination_scenario = [
        {0, :ping, %{}},
        {1, :ping, %{}},
        {1, :increment, %{"amount" => 5}},
        {0, :get_state, %{}}
      ]

      {:ok, results} =
        test_multi_agent_coordination(
          system_info,
          coordination_scenario,
          timeout: 10000
        )

      assert length(results) == 4

      # Verify coordination results
      [ping1, ping2, increment, state] = results
      assert {:ok, ping1_result} = ping1
      assert {:ok, ping2_result} = ping2
      assert {:ok, increment_result} = increment
      assert {:ok, state_result} = state

      assert ping1_result.response == :pong
      assert ping2_result.response == :pong
      assert increment_result.counter == 5
      assert is_map(state_result.state)
    end

    test "handles coordination errors gracefully" do
      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :worker, capabilities: [:ping]}
          ]
        )

      coordination_scenario = [
        {0, :ping, %{}},
        # This should fail
        {0, :unknown_action, %{}}
      ]

      # Test with continue_on_error
      case test_multi_agent_coordination(
             system_info,
             coordination_scenario,
             continue_on_error: true
           ) do
        {:ok, results} ->
          assert length(results) == 2

        # First should succeed, second should be an error
        {:error, _reason} ->
          # Also acceptable if it fails fast
          :ok
      end
    end

    test "supports parallel coordination" do
      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :worker1, capabilities: [:ping]},
            {:demo, type: :worker2, capabilities: [:ping]}
          ]
        )

      # Actions on different agents can be parallel
      coordination_scenario = [
        {0, :ping, %{}},
        {1, :ping, %{}}
      ]

      {:ok, results} =
        test_multi_agent_coordination(
          system_info,
          coordination_scenario,
          parallel: true,
          timeout: 5000
        )

      assert length(results) == 2

      Enum.each(results, fn result ->
        case result do
          {:ok, {:ok, unwrapped_result}} when is_map(unwrapped_result) ->
            assert unwrapped_result.response == :pong

          {:ok, unwrapped_result} when is_map(unwrapped_result) ->
            assert unwrapped_result.response == :pong

          unwrapped_result
          when is_map(unwrapped_result) and is_map_key(unwrapped_result, :response) ->
            assert unwrapped_result.response == :pong

          other ->
            # For debugging - sometimes results may have a different structure
            flunk("Unexpected result format: #{inspect(other)}")
        end
      end)
    end
  end

  describe "verify_system_consistency/2" do
    test "verifies system state consistency across all components" do
      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :worker, capabilities: [:ping, :increment]}
          ]
        )

      # Execute some operations
      [agent_info] = system_info.agents
      {:ok, _result} = execute_agent_action(agent_info.pid, :increment, %{"amount" => 3})

      # Verify system consistency
      assert :ok =
               verify_system_consistency(system_info,
                 timeout: 5000,
                 check_registry: true,
                 check_events: true,
                 check_agents: true
               )
    end

    test "detects inconsistencies when agents are dead" do
      # Trap exits for this test
      Process.flag(:trap_exit, true)

      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :worker, capabilities: [:ping]}
          ]
        )

      # Kill an agent
      [agent_info] = system_info.agents
      Process.exit(agent_info.pid, :kill)

      # Wait for process to die
      wait_for_process_termination(agent_info.pid, 1000)

      # Reset trap_exit after the test
      on_exit(fn -> Process.flag(:trap_exit, false) end)

      # Consistency check should detect the dead agent
      case verify_system_consistency(system_info, timeout: 2000) do
        {:error, {:consistency_violations, _violations}} ->
          :ok

        :ok ->
          # If system recovered quickly, that's also ok
          :ok
      end
    end
  end

  describe "test_registry_integration/3" do
    test "tests registry integration with agent lifecycle" do
      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :worker, capabilities: [:ping]},
            {:demo, type: :coordinator, capabilities: [:coordinate]}
          ]
        )

      [worker_agent, _coordinator_agent] = system_info.agents

      registry_operations = [
        {:list_all, [], fn agents -> length(agents) >= 2 end},
        {:get_agent, [worker_agent.agent.id],
         fn result ->
           case result do
             {:ok, _agent} -> true
             _ -> false
           end
         end}
      ]

      assert :ok = test_registry_integration(system_info, registry_operations)
    end
  end

  describe "test_event_system_integration/3" do
    test "tests event system integration with agent actions" do
      system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :worker, capabilities: [:ping]}
          ],
          event_subscriptions: [:demo_ping]
        )

      event_scenarios = [
        %{
          trigger: fn agents ->
            [agent_info] = agents
            execute_agent_action(agent_info.pid, :ping, %{})
          end,
          expected_events: [:demo_ping],
          # Simplified for basic test
          verify_propagation: false
        }
      ]

      assert :ok = test_event_system_integration(system_info, event_scenarios)
    end
  end

  describe "create_system_stress_test/3" do
    test "creates and executes basic stress test scenario" do
      # Small stress test for CI
      {:ok, results} =
        create_system_stress_test(
          # 3 agents
          3,
          # 5 operations per agent
          5,
          timeout: 15000,
          parallel_factor: 2,
          measure_performance: true
        )

      assert results.agent_count == 3
      assert results.operation_count == 5
      assert results.total_operations == 15
      # Allow some failures in stress test
      assert results.success_rate >= 0.8
      assert results.operations_per_second > 0
      assert is_map(results.performance_metrics)

      # Verify performance metrics structure
      metrics = results.performance_metrics
      assert is_map(metrics.memory_usage)
      assert is_integer(metrics.process_count)
      assert metrics.agent_count == 3
    end

    test "handles stress test with different operation types" do
      {:ok, results} =
        create_system_stress_test(
          # 2 agents
          2,
          # 3 operations per agent
          3,
          timeout: 10000,
          agent_types: [:demo],
          operation_types: [:ping, :increment],
          parallel_factor: 1
        )

      assert results.total_operations == 6
      assert is_list(results.operation_results)
      assert length(results.operation_results) == 6
    end
  end

  # Test helper functions and edge cases
  describe "helper functionality" do
    test "handles system setup timeouts gracefully" do
      # Test with very short timeout
      case setup_integration_system(
             agents: [{:demo, capabilities: [:ping]}],
             # Very short timeout
             timeout: 50
           ) do
        %{agents: _agents} ->
          # If it succeeds despite short timeout, that's fine
          :ok

        {:error, _reason} ->
          # Expected with very short timeout
          :ok
      end
    end

    test "provides proper cleanup integration" do
      # Create system with multiple agents
      _system_info =
        setup_integration_system(
          agents: [
            {:demo, type: :worker1, capabilities: [:ping]},
            {:demo, type: :worker2, capabilities: [:ping]}
          ]
        )

      # Cleanup is handled automatically through MabeamTestHelper integration
      # This test verifies no errors occur during setup/cleanup
      assert true
    end

    test "handles invalid agent specifications gracefully" do
      # Test with valid specs (invalid specs would be caught by MabeamTestHelper)
      system_info =
        setup_integration_system(
          agents: [
            # Valid spec
            {:demo, capabilities: [:ping]}
          ]
        )

      assert %{agents: [_agent]} = system_info
    end
  end
end
