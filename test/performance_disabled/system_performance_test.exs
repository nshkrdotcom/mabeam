defmodule SystemPerformanceTest do
  use ExUnit.Case, async: false
  import PerformanceTestHelper
  import MabeamTestHelper
  
  @moduletag :performance
  
  
  setup do
    # Ensure clean state for each test
    :ok = cleanup_all_test_resources()
    :ok
  end
  
  describe "system startup performance" do
    test "system startup performance meets baseline" do
      system_configs = [
        %{agents: 10, event_subscribers: 20}
      ]
      
      {:ok, results} = measure_system_startup_performance(system_configs)
      
      baseline = PerformanceBenchmarks.get_baseline(:system_startup)
      
      # Check startup time meets baseline
      assert results.startup_time <= baseline.startup_time_ms * 2  # Allow 2x baseline for test environment
      assert results.component_initialization_time <= baseline.component_initialization_ms * 2
      assert results.ready_time <= baseline.ready_time_ms * 2
      
      # Check baseline compliance
      {status, _analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :system_startup,
        results
      )
      
      assert status in [:ok, :warning]
    end
    
    test "system startup scales with configuration complexity" do
      simple_config = [%{agents: 5, event_subscribers: 10}]
      complex_config = [%{agents: 20, event_subscribers: 50}]
      
      {:ok, simple_results} = measure_system_startup_performance(simple_config)
      {:ok, complex_results} = measure_system_startup_performance(complex_config)
      
      # Complex configuration should take longer but not excessively
      startup_ratio = complex_results.startup_time / simple_results.startup_time
      assert startup_ratio <= 3.0  # Should not be more than 3x slower
      
      # Both should complete successfully
      assert simple_results.startup_time > 0
      assert complex_results.startup_time > 0
    end
    
    test "repeated system startup performance is consistent" do
      config = [%{agents: 8, event_subscribers: 15}]
      
      # Run startup test multiple times
      startup_times = Enum.map(1..5, fn _ ->
        {:ok, results} = measure_system_startup_performance(config)
        results.startup_time
      end)
      
      # Calculate coefficient of variation (std dev / mean)
      mean_time = Enum.sum(startup_times) / length(startup_times)
      variance = Enum.sum(Enum.map(startup_times, fn t -> :math.pow(t - mean_time, 2) end)) / length(startup_times)
      std_dev = :math.sqrt(variance)
      cv = std_dev / mean_time
      
      # Coefficient of variation should be reasonable (< 0.5 = 50%)
      assert cv < 0.5
      assert mean_time > 0
    end
  end
  
  describe "multi-agent coordination performance" do
    test "coordination performance meets baseline" do
      coordination_scenarios = [
        %{agent_count: 10, coordination_type: :simple, operations: 50}
      ]
      
      {:ok, results} = measure_coordination_performance(coordination_scenarios)
      
      baseline = PerformanceBenchmarks.get_baseline(:system_coordination)
      
      # Check coordination metrics
      assert results.coordination_latency_ms <= baseline.coordination_latency_ms * 2
      assert results.throughput_operations_per_sec >= baseline.throughput_operations_per_sec * 0.5
      assert results.success_rate >= baseline.success_rate * 0.9
      
      # Check baseline compliance
      {status, _analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :system_coordination,
        results
      )
      
      assert status in [:ok, :warning]
    end
    
    test "coordination scales with agent count" do
      small_scenario = [%{agent_count: 5, coordination_type: :simple, operations: 20}]
      large_scenario = [%{agent_count: 25, coordination_type: :simple, operations: 20}]
      
      {:ok, small_results} = measure_coordination_performance(small_scenario)
      {:ok, large_results} = measure_coordination_performance(large_scenario)
      
      # Latency should not increase dramatically with more agents
      latency_ratio = large_results.coordination_latency_ms / small_results.coordination_latency_ms
      assert latency_ratio <= 3.0
      
      # Throughput scaling should be reasonable
      throughput_ratio = large_results.throughput_operations_per_sec / small_results.throughput_operations_per_sec
      assert throughput_ratio >= 0.3  # Should not drop below 30% of original
      
      # Success rates should remain high
      assert small_results.success_rate >= 0.9
      assert large_results.success_rate >= 0.85
    end
    
    test "different coordination types performance comparison" do
      simple_scenario = [%{agent_count: 10, coordination_type: :simple, operations: 30}]
      complex_scenario = [%{agent_count: 10, coordination_type: :complex, operations: 30}]
      
      {:ok, simple_results} = measure_coordination_performance(simple_scenario)
      {:ok, complex_results} = measure_coordination_performance(complex_scenario)
      
      # Complex coordination should take longer but still be reasonable
      assert complex_results.coordination_latency_ms >= simple_results.coordination_latency_ms
      
      # Both should maintain good success rates
      assert simple_results.success_rate >= 0.95
      assert complex_results.success_rate >= 0.85
      
      # Throughput difference should be reasonable
      throughput_ratio = complex_results.throughput_operations_per_sec / simple_results.throughput_operations_per_sec
      assert throughput_ratio >= 0.4  # Complex should be at least 40% as fast as simple
    end
  end
  
  describe "system load performance" do
    test "system load performance meets baseline" do
      load_scenarios = [
        %{concurrent_agents: 50, operations_per_second: 1000, duration: 5000}
      ]
      
      {:ok, results} = measure_system_load_performance(load_scenarios)
      
      baseline = PerformanceBenchmarks.get_baseline(:system_load)
      
      # Check load performance metrics
      assert results.load_capacity_operations_per_sec >= baseline.load_capacity_operations_per_sec * 0.5
      assert results.performance_degradation_threshold <= baseline.performance_degradation_threshold * 2
      assert results.stability_score >= baseline.stability_score * 0.8
      
      # Check baseline compliance
      {status, _analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :system_load,
        results
      )
      
      assert status in [:ok, :warning]
    end
    
    test "system performance under increasing load" do
      light_load = [%{concurrent_agents: 20, operations_per_second: 500, duration: 3000}]
      heavy_load = [%{concurrent_agents: 100, operations_per_second: 2000, duration: 3000}]
      
      {:ok, light_results} = measure_system_load_performance(light_load)
      {:ok, heavy_results} = measure_system_load_performance(heavy_load)
      
      # System should handle both loads
      assert light_results.stability_score >= 0.9
      assert heavy_results.stability_score >= 0.7
      
      # Performance degradation should be within limits
      assert light_results.performance_degradation_threshold <= 0.1
      assert heavy_results.performance_degradation_threshold <= 0.3
      
      # Load capacity should scale reasonably
      capacity_ratio = heavy_results.load_capacity_operations_per_sec / light_results.load_capacity_operations_per_sec
      assert capacity_ratio >= 0.5  # Should maintain at least 50% capacity under heavy load
    end
    
    test "sustained load performance" do
      sustained_scenario = [%{concurrent_agents: 40, operations_per_second: 800, duration: 10000}]
      
      {:ok, results} = measure_system_load_performance(sustained_scenario)
      
      baseline = PerformanceBenchmarks.get_baseline(:system_load)
      
      # Sustained load should maintain stability
      assert results.stability_score >= baseline.stability_score * 0.8
      assert results.performance_degradation_threshold <= baseline.performance_degradation_threshold * 1.5
      
      # Load capacity should remain reasonable
      assert results.load_capacity_operations_per_sec >= baseline.load_capacity_operations_per_sec * 0.4
    end
  end
  
  describe "system memory efficiency" do
    test "memory efficiency meets baseline" do
      agent_counts = [10, 50, 100]
      
      {:ok, results} = measure_system_memory_efficiency(agent_counts)
      
      baseline = PerformanceBenchmarks.get_baseline(:system_memory)
      
      # Check memory efficiency metrics
      assert results.memory_efficiency_ratio >= baseline.memory_efficiency_ratio * 0.8
      assert results.max_tested_agents == 100
      
      # Memory scaling should be reasonable
      assert results.memory_scaling in [:linear, :logarithmic, :constant]
      
      # Check baseline compliance
      {status, _analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :system_memory,
        results
      )
      
      assert status in [:ok, :warning]
    end
    
    test "memory efficiency with different agent configurations" do
      small_agents = [5, 15, 25]
      large_agents = [50, 100, 200]
      
      {:ok, small_results} = measure_system_memory_efficiency(small_agents)
      {:ok, large_results} = measure_system_memory_efficiency(large_agents)
      
      # Both should have reasonable memory efficiency
      assert small_results.memory_efficiency >= 0.7
      assert large_results.memory_efficiency >= 0.6
      
      # Memory scaling should be consistent
      assert small_results.memory_scaling == large_results.memory_scaling
      
      # Maximum tested agents should be correct
      assert small_results.max_tested_agents == 25
      assert large_results.max_tested_agents == 200
    end
    
    test "memory efficiency over time" do
      # Test memory efficiency with time-based monitoring
      agent_counts = [20, 40, 60]
      
      # Run test multiple times to check consistency
      efficiency_scores = Enum.map(1..3, fn _ ->
        {:ok, results} = measure_system_memory_efficiency(agent_counts)
        results.memory_efficiency
      end)
      
      # All runs should have reasonable efficiency
      Enum.each(efficiency_scores, fn score ->
        assert score >= 0.6
        assert score <= 1.0
      end)
      
      # Efficiency should be relatively consistent
      min_efficiency = Enum.min(efficiency_scores)
      max_efficiency = Enum.max(efficiency_scores)
      efficiency_variation = max_efficiency - min_efficiency
      
      assert efficiency_variation <= 0.3  # Variation should be <= 30%
    end
  end
  
  describe "system integration performance" do
    test "full system performance workflow" do
      # Test complete system performance including all components
      
      # 1. System startup
      startup_config = [%{agents: 15, event_subscribers: 30}]
      {:ok, startup_results} = measure_system_startup_performance(startup_config)
      
      # 2. Coordination performance
      coordination_config = [%{agent_count: 15, coordination_type: :mixed, operations: 40}]
      {:ok, coordination_results} = measure_coordination_performance(coordination_config)
      
      # 3. Load performance
      load_config = [%{concurrent_agents: 30, operations_per_second: 600, duration: 4000}]
      {:ok, load_results} = measure_system_load_performance(load_config)
      
      # 4. Memory efficiency
      memory_config = [15, 30, 45]
      {:ok, memory_results} = measure_system_memory_efficiency(memory_config)
      
      # All components should perform reasonably
      assert startup_results.startup_time > 0
      assert coordination_results.success_rate >= 0.8
      assert load_results.stability_score >= 0.7
      assert memory_results.memory_efficiency >= 0.6
      
      # Compile overall system performance report
      system_performance = %{
        startup: startup_results,
        coordination: coordination_results,
        load: load_results,
        memory: memory_results
      }
      
      # Generate performance report
      report = generate_performance_report(system_performance, format: :text)
      
      assert is_binary(report)
      assert String.contains?(report, "Performance Test Report")
      assert String.contains?(report, "startup")
      assert String.contains?(report, "coordination")
    end
    
    test "system performance under mixed workload" do
      # Simulate a realistic mixed workload scenario
      
      # Create agents with different capabilities
      {:ok, _creation_results} = measure_agent_creation_performance(25, 
        agent_type: :demo, 
        capabilities: [:ping, :get_state]
      )
      
      # Test coordination under load
      coordination_scenario = [%{
        agent_count: 25, 
        coordination_type: :mixed, 
        operations: 60
      }]
      {:ok, coordination_results} = measure_coordination_performance(coordination_scenario)
      
      # Test system load with mixed operations
      load_scenario = [%{
        concurrent_agents: 25, 
        operations_per_second: 800, 
        duration: 6000
      }]
      {:ok, load_results} = measure_system_load_performance(load_scenario)
      
      # Mixed workload should maintain performance
      assert coordination_results.success_rate >= 0.8
      assert load_results.stability_score >= 0.75
      assert load_results.performance_degradation_threshold <= 0.25
      
      # Generate comprehensive baseline compliance report
      compliance_results = %{
        system_coordination: %{
          coordination_latency_ms: coordination_results.coordination_latency_ms,
          throughput_operations_per_sec: coordination_results.throughput_operations_per_sec,
          success_rate: coordination_results.success_rate
        },
        system_load: %{
          load_capacity_operations_per_sec: load_results.load_capacity_operations_per_sec,
          performance_degradation_threshold: load_results.performance_degradation_threshold,
          stability_score: load_results.stability_score
        }
      }
      
      report_card = PerformanceBenchmarks.generate_report_card(compliance_results)
      
      assert Map.has_key?(report_card, :overall_score)
      assert Map.has_key?(report_card, :component_scores)
      assert report_card.overall_score > 0.0
    end
  end
  
  describe "system performance regression detection" do
    test "detect system performance regressions" do
      # Simulate current results that show regression
      current_system_results = %{
        startup_time_ms: 250,  # Above baseline of 100ms
        coordination_latency_ms: 12.0,  # Above baseline of 5.0ms
        load_capacity_operations_per_sec: 3000  # Below baseline of 5000
      }
      
      startup_baseline = PerformanceBenchmarks.get_baseline(:system_startup)
      coordination_baseline = PerformanceBenchmarks.get_baseline(:system_coordination)
      load_baseline = PerformanceBenchmarks.get_baseline(:system_load)
      
      # Check for regressions in each component
      startup_regression = detect_performance_regression(
        %{startup_time_ms: current_system_results.startup_time_ms},
        startup_baseline,
        0.1
      )
      
      coordination_regression = detect_performance_regression(
        %{coordination_latency_ms: current_system_results.coordination_latency_ms},
        coordination_baseline,
        0.1
      )
      
      load_regression = detect_performance_regression(
        %{load_capacity_operations_per_sec: current_system_results.load_capacity_operations_per_sec},
        load_baseline,
        0.1
      )
      
      # Should detect regressions
      assert startup_regression.regression_detected == true
      assert coordination_regression.regression_detected == true
      assert load_regression.regression_detected == true
      
      # All should have recommendations
      assert String.contains?(startup_regression.recommendation, "regression detected")
      assert String.contains?(coordination_regression.recommendation, "regression detected")
      assert String.contains?(load_regression.recommendation, "regression detected")
    end
    
    test "system performance comparison over time" do
      # Simulate performance results from different time periods
      baseline_period = %{
        startup_time_ms: 95,
        coordination_latency_ms: 4.8,
        load_capacity_operations_per_sec: 5200,
        memory_efficiency_ratio: 0.87
      }
      
      current_period = %{
        startup_time_ms: 105,  # Slight increase
        coordination_latency_ms: 4.5,  # Improvement
        load_capacity_operations_per_sec: 5400,  # Improvement
        memory_efficiency_ratio: 0.84  # Slight decrease
      }
      
      comparison = PerformanceBenchmarks.compare_performance_results(
        :system_startup,
        current_period,
        baseline_period,
        0.15  # 15% regression threshold
      )
      
      assert Map.has_key?(comparison, :component)
      assert Map.has_key?(comparison, :regression_analysis)
      assert Map.has_key?(comparison, :improvement_analysis)
      assert Map.has_key?(comparison, :recommendations)
      
      # Should not detect major regressions within 15% threshold
      assert comparison.regression_analysis.regressions_detected == false
      
      # Should detect improvements
      assert comparison.improvement_analysis.improvements_detected == true
      assert length(comparison.improvement_analysis.improved_metrics) > 0
    end
  end
  
  describe "system performance stress testing" do
    test "system handles extreme load conditions" do
      # Test system under extreme conditions
      extreme_load = [%{
        concurrent_agents: 200, 
        operations_per_second: 5000, 
        duration: 8000
      }]
      
      {:ok, results} = measure_system_load_performance(extreme_load)
      
      # System should maintain some level of functionality
      assert results.stability_score >= 0.5  # At least 50% stability
      assert results.load_capacity_operations_per_sec > 0
      
      # Performance degradation is expected but should not be complete failure
      assert results.performance_degradation_threshold <= 0.7  # No more than 70% degradation
    end
    
    test "system recovery after load stress" do
      # Test system recovery capabilities
      
      # 1. Apply heavy load
      heavy_load = [%{concurrent_agents: 150, operations_per_second: 4000, duration: 5000}]
      {:ok, stress_results} = measure_system_load_performance(heavy_load)
      
      # 2. Test normal load after stress
      normal_load = [%{concurrent_agents: 30, operations_per_second: 600, duration: 3000}]
      {:ok, recovery_results} = measure_system_load_performance(normal_load)
      
      # System should recover to reasonable performance
      assert recovery_results.stability_score >= 0.8
      assert recovery_results.performance_degradation_threshold <= 0.2
      
      # Recovery performance should be better than stress performance
      assert recovery_results.stability_score >= stress_results.stability_score
      assert recovery_results.load_capacity_operations_per_sec >= stress_results.load_capacity_operations_per_sec * 0.8
    end
  end
end