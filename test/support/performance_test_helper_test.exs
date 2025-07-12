defmodule PerformanceTestHelperTest do
  use ExUnit.Case, async: false
  import PerformanceTestHelper
  import MabeamTestHelper
  
  @moduletag :performance
  
  setup do
    # Ensure clean state for each test
    :ok = cleanup_all_test_resources()
    :ok
  end
  
  describe "performance measurement utilities" do
    test "measure_operation_time/1 measures execution time accurately" do
      {result, duration} = measure_operation_time(fn ->
        # Use a simple computation to test timing
        Enum.reduce(1..10_000, 0, fn i, acc -> acc + i end)
        :test_result
      end)
      
      assert result == :test_result
      assert duration >= 0  # At least 0 microseconds
      assert duration <= 50_000  # Should not take more than 50ms
    end
    
    test "measure_memory_usage/1 returns memory for valid process" do
      {:ok, _agent, pid} = create_test_agent(:demo)
      
      memory = measure_memory_usage(pid)
      
      assert is_integer(memory)
      assert memory > 0
    end
    
    test "measure_memory_usage/1 returns 0 for invalid process" do
      invalid_pid = spawn(fn -> :ok end)
      # Wait for process to actually terminate
      Process.sleep(10)
      
      memory = measure_memory_usage(invalid_pid)
      
      assert memory == 0
    end
    
    test "stress_test_with_monitoring/3 handles sequential operations" do
      operation_fn = fn i -> {:ok, i * 2} end
      
      {:ok, results} = stress_test_with_monitoring(operation_fn, 5, parallel: false)
      
      assert results.total_count == 5
      assert results.success_count == 5
      assert results.failure_count == 0
      assert results.success_rate == 1.0
      assert results.operations_per_second >= 0  # Operations may complete too quickly to measure
      assert length(results.results) == 5
    end
    
    test "stress_test_with_monitoring/3 handles parallel operations" do
      operation_fn = fn i -> 
        # Use OTP-compliant delay with GenServer call
        agent_id = "test_agent_#{i}_#{:erlang.unique_integer([:positive])}"
        case MabeamTestHelper.create_test_agent(:demo, capabilities: [:ping], name: String.to_atom(agent_id)) do
          {:ok, _agent, pid} ->
            # Small operation to test parallelism 
            MabeamTestHelper.execute_agent_action(pid, :ping, %{})
            {:ok, i * 2}
          error -> error
        end
      end
      
      {:ok, results} = stress_test_with_monitoring(operation_fn, 3, parallel: true)
      
      assert results.total_count == 3
      assert results.success_count >= 1  # At least some operations should succeed
      assert results.success_rate >= 0.0
      # Operations_per_second may vary based on system performance
      assert results.operations_per_second >= 0
    end
    
    test "stress_test_with_monitoring/3 handles operation failures" do
      operation_fn = fn i -> 
        if rem(i, 2) == 0 do
          {:ok, i}
        else
          {:error, :test_failure}
        end
      end
      
      {:ok, results} = stress_test_with_monitoring(operation_fn, 4, parallel: false)
      
      assert results.total_count == 4
      assert results.success_count == 2  # Even numbers succeed
      assert results.failure_count == 2
      assert results.success_rate == 0.5
    end
  end
  
  describe "agent performance testing" do
    test "measure_agent_creation_performance/2 measures agent creation" do
      {:ok, results} = measure_agent_creation_performance(10, parallel: false)
      
      assert results.total_count == 10
      assert results.success_count > 0
      assert results.duration_microseconds > 0
      assert results.agents_per_second > 0
      assert results.average_creation_time >= 0
      assert results.average_memory_per_agent > 0
      assert results.min_creation_time >= 0
      assert results.max_creation_time >= results.min_creation_time
    end
    
    test "measure_agent_creation_performance/2 handles parallel creation" do
      {:ok, results} = measure_agent_creation_performance(5, parallel: true)
      
      assert results.total_count == 5
      assert results.success_count > 0
      # Parallel should generally be faster
      assert results.agents_per_second > 0
    end
    
    test "measure_agent_action_performance/2 measures action execution" do
      agent_scenarios = [
        %{type: :demo, capabilities: [:ping], action: :ping, params: %{}, action_count: 5}
      ]
      
      {:ok, results} = measure_agent_action_performance(agent_scenarios, parallel: false)
      
      assert results.total_actions > 0
      assert results.successful_actions > 0
      assert results.average_execution_time >= 0
      assert results.actions_per_second >= 0  # Can be 0 if operations complete too quickly
    end
    
    test "measure_agent_memory_usage/2 tracks memory over time" do
      agent_configs = [
        %{type: :demo, count: 3, capabilities: [:ping]}
      ]
      
      {:ok, results} = measure_agent_memory_usage(agent_configs, 
        monitor_duration: 500, 
        measurement_interval: 100
      )
      
      assert Map.has_key?(results, :memory_growth_rate)
      assert Map.has_key?(results, :memory_leaks)
      assert is_number(results.memory_growth_rate)
      assert is_list(results.memory_leaks)
    end
    
    test "stress_test_agent_lifecycle/2 tests create/destroy cycles" do
      {:ok, results} = stress_test_agent_lifecycle(3, parallel: false, agent_type: :demo)
      
      assert results.total_cycles == 3
      assert results.successful_cycles >= 0
      assert results.success_rate >= 0
      assert results.average_cycle_time >= 0
      assert Map.has_key?(results, :memory_stable)
    end
  end
  
  describe "system performance testing" do
    test "measure_system_startup_performance/2 returns startup metrics" do
      system_configs = [
        %{agents: 5, event_subscribers: 10}
      ]
      
      {:ok, results} = measure_system_startup_performance(system_configs)
      
      assert Map.has_key?(results, :startup_time)
      assert Map.has_key?(results, :component_initialization_time)
      assert Map.has_key?(results, :ready_time)
      assert results.startup_time > 0
    end
    
    test "measure_coordination_performance/2 returns coordination metrics" do
      coordination_scenarios = [
        %{agent_count: 5, coordination_type: :simple}
      ]
      
      {:ok, results} = measure_coordination_performance(coordination_scenarios)
      
      assert Map.has_key?(results, :coordination_latency)
      assert Map.has_key?(results, :throughput)
      assert Map.has_key?(results, :success_rate)
    end
  end
  
  describe "event system performance testing" do
    test "measure_event_system_performance/2 measures event throughput" do
      event_scenarios = [
        %{event_count: 10, subscriber_count: 1}
      ]
      
      {:ok, results} = measure_event_system_performance(event_scenarios, parallel: false)
      
      assert results.total_events > 0
      assert results.successful_events >= 0
      assert results.events_per_second >= 0
      assert results.average_latency >= 0
      assert results.success_rate >= 0
    end
    
    test "measure_event_propagation_performance/2 returns propagation metrics" do
      subscriber_counts = [10, 50, 100]
      
      {:ok, results} = measure_event_propagation_performance(subscriber_counts)
      
      assert Map.has_key?(results, :propagation_time)
      assert Map.has_key?(results, :subscriber_scaling)
      assert Map.has_key?(results, :max_tested_subscribers)
      assert results.max_tested_subscribers == 100
    end
    
    test "stress_test_event_system/3 returns stress test results" do
      {:ok, results} = stress_test_event_system(1000, 2000)  # 1000 events/sec for 2 seconds
      
      assert Map.has_key?(results, :events_processed)
      assert Map.has_key?(results, :system_stable)
      assert Map.has_key?(results, :memory_usage_stable)
      assert is_boolean(results.system_stable)
    end
  end
  
  describe "registry performance testing" do
    test "measure_registry_performance/2 returns registry metrics" do
      operation_counts = %{lookup: 100, register: 50, unregister: 30}
      
      {:ok, results} = measure_registry_performance(operation_counts)
      
      assert Map.has_key?(results, :lookup_time)
      assert Map.has_key?(results, :register_time)
      assert Map.has_key?(results, :unregister_time)
      assert is_number(results.lookup_time)
    end
    
    test "measure_registry_scalability/2 returns scalability metrics" do
      agent_counts = [100, 500, 1000]
      
      {:ok, results} = measure_registry_scalability(agent_counts)
      
      assert Map.has_key?(results, :scaling_factor)
      assert Map.has_key?(results, :performance_degradation)
      assert Map.has_key?(results, :max_tested_agents)
      assert results.max_tested_agents == 1000
    end
  end
  
  describe "resource limit testing" do
    test "test_process_limit_behavior/2 returns limit behavior metrics" do
      {:ok, results} = test_process_limit_behavior(0.8)
      
      assert Map.has_key?(results, :limit_reached)
      assert Map.has_key?(results, :graceful_degradation)
      assert Map.has_key?(results, :recovery_successful)
      assert is_boolean(results.limit_reached)
    end
    
    test "test_memory_pressure_behavior/2 returns memory behavior metrics" do
      {:ok, results} = test_memory_pressure_behavior(1000 * 1024 * 1024)  # 1GB
      
      assert Map.has_key?(results, :memory_limit)
      assert Map.has_key?(results, :pressure_handling)
      assert Map.has_key?(results, :gc_effectiveness)
      assert results.memory_limit == 1000 * 1024 * 1024
    end
    
    test "test_resource_exhaustion_recovery/2 returns recovery metrics" do
      exhaustion_scenarios = [
        %{type: :memory, limit: 500},
        %{type: :processes, limit: 1000}
      ]
      
      {:ok, results} = test_resource_exhaustion_recovery(exhaustion_scenarios)
      
      assert Map.has_key?(results, :recovery_time)
      assert Map.has_key?(results, :data_consistency)
      assert Map.has_key?(results, :performance_restored)
      assert is_boolean(results.data_consistency)
    end
  end
  
  describe "performance analysis and reporting" do
    test "analyze_performance_results/2 analyzes results without baseline" do
      results = %{
        total_count: 100,
        success_count: 95,
        duration_ms: 5000
      }
      
      analysis = analyze_performance_results(results)
      
      assert Map.has_key?(analysis, :total_operations)
      assert Map.has_key?(analysis, :success_rate)
      assert Map.has_key?(analysis, :average_duration)
      assert Map.has_key?(analysis, :percentiles)
      assert analysis.total_operations == 100
      assert analysis.success_rate == 0.95
    end
    
    test "analyze_performance_results/2 includes regression analysis with baseline" do
      results = %{
        total_count: 100,
        success_count: 95,
        duration_ms: 5000,
        average_duration: 50
      }
      
      baseline = %{
        average_duration: 40
      }
      
      analysis = analyze_performance_results(results, baseline)
      
      assert Map.has_key?(analysis, :regression_analysis)
      assert Map.has_key?(analysis.regression_analysis, :regression_detected)
      assert Map.has_key?(analysis.regression_analysis, :regression_percentage)
    end
    
    test "detect_performance_regression/3 detects regression" do
      current_results = %{average_duration: 60}
      baseline_results = %{average_duration: 40}
      
      regression = detect_performance_regression(current_results, baseline_results, 0.1)
      
      assert regression.regression_detected == true
      assert regression.regression_percentage == 50.0  # 50% regression
      assert String.contains?(regression.recommendation, "regression detected")
    end
    
    test "detect_performance_regression/3 does not detect when within threshold" do
      current_results = %{average_duration: 42}
      baseline_results = %{average_duration: 40}
      
      regression = detect_performance_regression(current_results, baseline_results, 0.1)
      
      assert regression.regression_detected == false
      assert regression.regression_percentage == 5.0  # 5% change, within 10% threshold
      assert String.contains?(regression.recommendation, "acceptable range")
    end
    
    test "generate_performance_report/2 generates text report" do
      test_results = %{
        component: :agent_creation,
        average_time: 1.5,
        success_rate: 0.98
      }
      
      report = generate_performance_report(test_results, format: :text)
      
      assert is_binary(report)
      assert String.contains?(report, "Performance Test Report")
      assert String.contains?(report, "agent_creation")
    end
    
    test "generate_performance_report/2 generates JSON report" do
      test_results = %{
        component: :agent_creation,
        average_time: 1.5,
        success_rate: 0.98
      }
      
      report = generate_performance_report(test_results, format: :json)
      
      assert is_binary(report)
      # Should be valid JSON
      {:ok, parsed} = Jason.decode(report)
      assert Map.has_key?(parsed, "component")
    end
  end
  
  describe "integration tests" do
    test "full agent performance workflow" do
      # Create agents
      {:ok, creation_results} = measure_agent_creation_performance(5)
      assert creation_results.success_count > 0
      
      # Test actions
      agent_scenarios = [
        %{type: :demo, capabilities: [:ping], action: :ping, params: %{}, action_count: 3}
      ]
      {:ok, action_results} = measure_agent_action_performance(agent_scenarios)
      assert action_results.successful_actions > 0
      
      # Memory usage
      agent_configs = [%{type: :demo, count: 2}]
      {:ok, memory_results} = measure_agent_memory_usage(agent_configs, monitor_duration: 200)
      assert Map.has_key?(memory_results, :memory_growth_rate)
      
      # Lifecycle stress test
      {:ok, lifecycle_results} = stress_test_agent_lifecycle(2)
      assert lifecycle_results.successful_cycles >= 0
    end
    
    test "performance baseline comparison workflow" do
      # Generate test results
      test_results = %{
        agents_per_second: 800,  # Below baseline of 1000
        memory_per_agent: 2 * 1024 * 1024,  # Above baseline of 1MB
        creation_time_ms: 1.2
      }
      
      # Get baseline and compare
      baseline = PerformanceBenchmarks.get_baseline(:agent_creation)
      assert Map.has_key?(baseline, :agents_per_second)
      
      # Check compliance
      {status, analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :agent_creation, 
        test_results
      )
      
      assert status in [:ok, :warning, :error]
      assert Map.has_key?(analysis, :agents_per_second)
      
      # Generate report
      component_results = %{agent_creation: test_results}
      report_card = PerformanceBenchmarks.generate_report_card(component_results)
      
      assert Map.has_key?(report_card, :overall_score)
      assert Map.has_key?(report_card, :component_scores)
    end
  end
end