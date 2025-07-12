defmodule EventPerformanceTest do
  use ExUnit.Case, async: false
  import PerformanceTestHelper
  import MabeamTestHelper
  
  @moduletag :performance
  
  
  setup do
    # Ensure clean state for each test
    :ok = cleanup_all_test_resources()
    :ok
  end
  
  describe "event system throughput and latency" do
    test "event system performance meets baseline" do
      event_scenarios = [
        %{event_count: 1000, subscriber_count: 10}
      ]
      
      {:ok, results} = measure_event_system_performance(event_scenarios, parallel: false)
      
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      
      # Check performance metrics against baseline
      assert results.events_per_second >= baseline.events_per_second * 0.5
      assert results.average_latency <= baseline.average_latency_ms * 1000 * 2  # Convert to microseconds, allow 2x
      assert results.success_rate >= 0.9
      
      # Check baseline compliance
      baseline_format = %{
        events_per_second: results.events_per_second,
        average_latency_ms: results.average_latency / 1000,
        success_rate: results.success_rate
      }
      
      {status, _analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :event_system,
        baseline_format
      )
      
      assert status in [:ok, :warning]
    end
    
    @tag :slow
    test "event system performance with parallel processing" do
      event_scenarios = [
        %{event_count: 500, subscriber_count: 5}
      ]
      
      # Test sequential processing
      {:ok, sequential_results} = measure_event_system_performance(event_scenarios, parallel: false)
      
      # Test parallel processing
      {:ok, parallel_results} = measure_event_system_performance(event_scenarios, parallel: true)
      
      # Both should succeed
      assert sequential_results.successful_events > 0
      assert parallel_results.successful_events > 0
      
      # Parallel should generally be faster or equivalent
      assert parallel_results.events_per_second >= sequential_results.events_per_second * 0.8
      
      # Success rates should be high for both
      assert sequential_results.success_rate >= 0.9
      assert parallel_results.success_rate >= 0.85  # Allow slight degradation for parallel complexity
    end
    
    test "event system performance with different event volumes" do
      small_scenario = [%{event_count: 100, subscriber_count: 5}]
      large_scenario = [%{event_count: 2000, subscriber_count: 5}]
      
      {:ok, small_results} = measure_event_system_performance(small_scenario)
      {:ok, large_results} = measure_event_system_performance(large_scenario)
      
      # Both should process events successfully
      assert small_results.successful_events >= 90  # At least 90% of 100
      assert large_results.successful_events >= 1800  # At least 90% of 2000
      
      # Throughput should scale reasonably
      throughput_ratio = large_results.events_per_second / small_results.events_per_second
      assert throughput_ratio >= 0.5  # Large volume should maintain at least 50% throughput
      
      # Latency should not increase dramatically
      if small_results.average_latency > 0 do
        latency_ratio = large_results.average_latency / small_results.average_latency
        assert latency_ratio <= 3.0  # Should not be more than 3x slower
      else
        # If small scenario latency is 0, just ensure large scenario latency is reasonable
        assert large_results.average_latency <= 50_000  # 50ms in microseconds
      end
    end
    
    test "event system latency distribution" do
      event_scenarios = [
        %{event_count: 200, subscriber_count: 8}
      ]
      
      {:ok, results} = measure_event_system_performance(event_scenarios)
      
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      
      # Average latency should be reasonable
      assert results.average_latency <= baseline.max_latency_ms * 1000  # Convert to microseconds
      
      # Most events should process quickly
      assert results.success_rate >= 0.95
      
      # Events per second should be substantial
      assert results.events_per_second >= baseline.events_per_second * 0.3
    end
  end
  
  describe "event propagation performance" do
    test "event propagation performance meets baseline" do
      subscriber_counts = [10, 50, 100]
      
      {:ok, results} = measure_event_propagation_performance(subscriber_counts)
      
      baseline = PerformanceBenchmarks.get_baseline(:event_propagation)
      
      # Check propagation performance
      assert results.propagation_time <= baseline.propagation_time_per_subscriber_ms * 100 * 2  # Max subscribers * 2x allowance
      assert results.max_tested_subscribers == 100
      
      # Scaling should be reasonable
      assert results.subscriber_scaling in [:linear, :logarithmic, :constant]
      
      # Check baseline compliance
      {status, _analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :event_propagation,
        results
      )
      
      assert status in [:ok, :warning]
    end
    
    test "event propagation scales with subscriber count" do
      few_subscribers = [5, 10]
      many_subscribers = [50, 100, 200]
      
      {:ok, few_results} = measure_event_propagation_performance(few_subscribers)
      {:ok, many_results} = measure_event_propagation_performance(many_subscribers)
      
      # Both should complete successfully
      assert few_results.propagation_time > 0
      assert many_results.propagation_time > 0
      
      # More subscribers should take longer but not excessively
      time_ratio = many_results.propagation_time / few_results.propagation_time
      assert time_ratio <= 10.0  # Should not be more than 10x slower
      
      # Maximum tested counts should be correct
      assert few_results.max_tested_subscribers == 10
      assert many_results.max_tested_subscribers == 200
    end
    
    test "event propagation with pattern matching" do
      # Test propagation performance with different patterns
      subscriber_counts = [20, 40]
      
      {:ok, results} = measure_event_propagation_performance(subscriber_counts)
      
      baseline = PerformanceBenchmarks.get_baseline(:event_propagation)
      
      # Pattern matching should not cause excessive delays
      assert results.propagation_time <= baseline.propagation_time_per_subscriber_ms * 40 * 3
      
      # Scaling should handle pattern complexity
      assert results.subscriber_scaling in [:linear, :logarithmic]
      
      # Should handle moderate subscriber counts efficiently
      assert results.max_tested_subscribers == 40
    end
  end
  
  describe "event system stress testing" do
    test "event system stress test meets baseline" do
      {:ok, results} = stress_test_event_system(5000, 4000)  # 5000 events/sec for 4 seconds
      
      baseline = PerformanceBenchmarks.get_baseline(:event_stress)
      
      # Check stress performance
      assert results.events_processed >= baseline.sustained_event_rate * 3  # 3 seconds minimum
      assert results.system_stable == true
      assert results.memory_usage_stable == true
      
      # Check baseline compliance
      baseline_format = %{
        sustained_event_rate: results.events_processed / 4,  # Events per second
        system_stability_threshold: if(results.system_stable, do: 1.0, else: 0.0),
        memory_stability_threshold: if(results.memory_usage_stable, do: 1.0, else: 0.0)
      }
      
      {status, _analysis} = PerformanceBenchmarks.check_baseline_compliance(
        :event_stress,
        baseline_format
      )
      
      assert status in [:ok, :warning]
    end
    
    test "sustained high-rate event processing" do
      # Test sustained event processing
      {:ok, results} = stress_test_event_system(8000, 6000)  # 8000 events/sec for 6 seconds
      
      baseline = PerformanceBenchmarks.get_baseline(:event_stress)
      
      # Should process most events even under high load
      expected_events = 8000 * 6 / 1000  # Total expected events
      assert results.events_processed >= expected_events * 0.7  # At least 70% processed
      
      # System should remain stable
      assert results.system_stable == true
      assert results.memory_usage_stable == true
      
      # Should handle sustained rate close to baseline
      sustained_rate = results.events_processed / 6
      assert sustained_rate >= baseline.sustained_event_rate * 0.6
    end
    
    test "burst event processing performance" do
      # Test burst capability
      {:ok, results} = stress_test_event_system(15000, 2000)  # 15000 events/sec for 2 seconds (burst)
      
      baseline = PerformanceBenchmarks.get_baseline(:event_stress)
      
      # Should handle burst close to baseline burst rate
      burst_rate = results.events_processed / 2
      assert burst_rate >= baseline.burst_event_rate * 0.5
      
      # System should handle burst without complete failure
      assert results.system_stable == true
      
      # Memory should remain stable even during burst
      assert results.memory_usage_stable == true
      
      # Should process significant portion of burst events
      expected_events = 15000 * 2 / 1000
      assert results.events_processed >= expected_events * 0.5  # At least 50% during burst
    end
    
    test "event system recovery after stress" do
      # Apply stress load
      {:ok, stress_results} = stress_test_event_system(12000, 3000)
      
      # Test normal load after stress
      normal_scenarios = [%{event_count: 500, subscriber_count: 10}]
      {:ok, recovery_results} = measure_event_system_performance(normal_scenarios)
      
      # System should recover to normal performance
      assert recovery_results.success_rate >= 0.9
      assert recovery_results.events_per_second > 0
      
      # Recovery should show good performance
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      assert recovery_results.events_per_second >= baseline.events_per_second * 0.7
      assert recovery_results.average_latency <= baseline.average_latency_ms * 1000 * 2
    end
  end
  
  describe "event system integration performance" do
    test "event system with multiple agent subscribers" do
      # Create multiple agents as event subscribers
      agent_configs = [%{type: :demo, count: 15, capabilities: [:ping]}]
      {:ok, _memory_results} = measure_agent_memory_usage(agent_configs, monitor_duration: 1000)
      
      # Test event system performance with agent subscribers
      event_scenarios = [%{event_count: 300, subscriber_count: 15}]
      {:ok, results} = measure_event_system_performance(event_scenarios)
      
      # Should handle agent subscribers efficiently
      assert results.successful_events >= 270  # At least 90% success
      assert results.success_rate >= 0.9
      assert results.events_per_second > 0
      
      # Latency should be reasonable with agent subscribers
      assert results.average_latency <= 50_000  # 50ms in microseconds
    end
    
    test "event system performance with mixed event types" do
      # Subscribe to multiple event types
      :ok = subscribe_to_events([:perf_test_event, :mixed_test_event, :batch_test_event])
      
      # Test performance with mixed event types
      mixed_scenarios = [%{event_count: 400, subscriber_count: 8, event_types: 3}]
      {:ok, results} = measure_event_system_performance(mixed_scenarios)
      
      # Should handle mixed event types efficiently
      assert results.successful_events >= 360  # At least 90% success
      assert results.success_rate >= 0.9
      
      # Performance should remain good with mixed types
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      assert results.events_per_second >= baseline.events_per_second * 0.6
    end
    
    test "event system performance with pattern subscriptions" do
      # Test pattern-based subscriptions
      :ok = subscribe_to_events(["perf_test.*", "pattern.*"])
      
      # Generate events matching patterns
      pattern_scenarios = [%{event_count: 250, subscriber_count: 6, use_patterns: true}]
      {:ok, results} = measure_event_system_performance(pattern_scenarios)
      
      # Pattern matching should not severely impact performance
      assert results.successful_events >= 225  # At least 90% success
      assert results.success_rate >= 0.9
      
      # Pattern matching latency should be reasonable
      assert results.average_latency <= 30_000  # 30ms in microseconds
      
      # Should maintain decent throughput with patterns
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      assert results.events_per_second >= baseline.events_per_second * 0.4
    end
  end
  
  describe "event system performance regression detection" do
    test "detect event system performance regressions" do
      # Simulate current results that show regression
      current_event_results = %{
        events_per_second: 6000,  # Below baseline of 10000
        average_latency_ms: 3.0,  # Above baseline of 1.0ms
        success_rate: 0.92  # Below baseline of 0.95
      }
      
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      
      # Check for regressions
      regression = detect_performance_regression(current_event_results, baseline, 0.1)
      
      # Should detect throughput regression
      assert regression.regression_detected == true
      assert String.contains?(regression.recommendation, "regression detected")
    end
    
    test "event system performance improvements detection" do
      # Simulate improved results
      improved_results = %{
        events_per_second: 12000,  # Above baseline of 10000
        average_latency_ms: 0.8,  # Below baseline of 1.0ms
        success_rate: 0.97  # Above baseline of 0.95
      }
      
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      
      # Check for improvements
      regression = detect_performance_regression(improved_results, baseline, 0.1)
      
      # Should not detect regression (it's an improvement)
      assert regression.regression_detected == false
      assert String.contains?(regression.recommendation, "acceptable range")
    end
    
    test "event propagation performance comparison" do
      # Compare propagation performance over time
      baseline_propagation = %{
        propagation_time: 25.0,
        max_tested_subscribers: 100,
        subscriber_scaling: :logarithmic
      }
      
      current_propagation = %{
        propagation_time: 35.0,  # Slower than baseline
        max_tested_subscribers: 150,
        subscriber_scaling: :logarithmic
      }
      
      comparison = PerformanceBenchmarks.compare_performance_results(
        :event_propagation,
        current_propagation,
        baseline_propagation,
        0.2  # 20% regression threshold
      )
      
      assert Map.has_key?(comparison, :regression_analysis)
      assert Map.has_key?(comparison, :improvement_analysis)
      
      # Should detect regression in propagation time
      assert comparison.regression_analysis.regressions_detected == true
      assert :propagation_time in comparison.regression_analysis.regressed_metrics
    end
  end
  
  describe "comprehensive event system performance testing" do
    test "full event system performance workflow" do
      # 1. Basic throughput test
      basic_scenarios = [%{event_count: 500, subscriber_count: 10}]
      {:ok, throughput_results} = measure_event_system_performance(basic_scenarios)
      
      # 2. Propagation test
      subscriber_counts = [10, 25, 50]
      {:ok, propagation_results} = measure_event_propagation_performance(subscriber_counts)
      
      # 3. Stress test
      {:ok, stress_results} = stress_test_event_system(8000, 3000)
      
      # All tests should pass
      assert throughput_results.success_rate >= 0.9
      assert propagation_results.propagation_time > 0
      assert stress_results.system_stable == true
      
      # Compile comprehensive results
      event_performance = %{
        throughput: throughput_results,
        propagation: propagation_results,
        stress: stress_results
      }
      
      # Generate performance report
      report = generate_performance_report(event_performance, format: :text)
      
      assert is_binary(report)
      assert String.contains?(report, "Performance Test Report")
      assert String.contains?(report, "throughput")
      assert String.contains?(report, "propagation")
      assert String.contains?(report, "stress")
    end
    
    test "event system baseline compliance report" do
      # Run comprehensive tests and check baseline compliance
      
      # Throughput test
      throughput_scenarios = [%{event_count: 800, subscriber_count: 12}]
      {:ok, throughput_results} = measure_event_system_performance(throughput_scenarios)
      
      # Propagation test
      {:ok, propagation_results} = measure_event_propagation_performance([20, 40])
      
      # Stress test
      {:ok, stress_results} = stress_test_event_system(6000, 4000)
      
      # Convert to baseline format
      compliance_results = %{
        event_system: %{
          events_per_second: throughput_results.events_per_second,
          average_latency_ms: throughput_results.average_latency / 1000,
          success_rate: throughput_results.success_rate
        },
        event_propagation: %{
          propagation_time: propagation_results.propagation_time,
          max_tested_subscribers: propagation_results.max_tested_subscribers,
          subscriber_scaling: propagation_results.subscriber_scaling
        },
        event_stress: %{
          sustained_event_rate: stress_results.events_processed / 4,
          system_stability_threshold: if(stress_results.system_stable, do: 1.0, else: 0.0),
          memory_stability_threshold: if(stress_results.memory_usage_stable, do: 1.0, else: 0.0)
        }
      }
      
      # Generate report card
      report_card = PerformanceBenchmarks.generate_report_card(compliance_results)
      
      assert Map.has_key?(report_card, :overall_score)
      assert Map.has_key?(report_card, :component_scores)
      assert Map.has_key?(report_card, :summary)
      
      # Overall score should be reasonable
      assert report_card.overall_score > 0.0
      assert report_card.overall_score <= 1.5
      
      # Should have scores for each event component
      assert Map.has_key?(report_card.component_scores, :event_system)
      assert Map.has_key?(report_card.component_scores, :event_propagation)
      assert Map.has_key?(report_card.component_scores, :event_stress)
    end
    
    test "event system performance under realistic workload" do
      # Create a realistic mixed workload
      
      # Setup: Create agents that will be event subscribers
      agent_configs = [%{type: :demo, count: 20, capabilities: [:ping]}]
      {:ok, _memory_results} = measure_agent_memory_usage(agent_configs, monitor_duration: 500)
      
      # Subscribe to various event patterns
      :ok = subscribe_to_events([
        :agent_action, :system_event, :performance_metric,
        "agent.*", "system.*"
      ])
      
      # Test mixed event load
      realistic_scenarios = [%{
        event_count: 600, 
        subscriber_count: 25,  # Agents + pattern subscribers
        event_types: 5
      }]
      
      {:ok, results} = measure_event_system_performance(realistic_scenarios, parallel: true)
      
      # Realistic workload should maintain good performance
      assert results.success_rate >= 0.85
      assert results.events_per_second >= 100  # Minimum reasonable throughput
      
      # Latency should be acceptable for realistic workload
      assert results.average_latency <= 100_000  # 100ms in microseconds
      
      # Most events should be processed successfully
      assert results.successful_events >= results.total_events * 0.85
      
      # Generate performance analysis
      baseline = PerformanceBenchmarks.get_baseline(:event_system)
      analysis = analyze_performance_results(
        %{
          events_per_second: results.events_per_second,
          average_latency_ms: results.average_latency / 1000,
          success_rate: results.success_rate
        },
        baseline
      )
      
      assert Map.has_key?(analysis, :success_rate)
      assert Map.has_key?(analysis, :average_duration)
      assert analysis.success_rate >= 0.85
    end
  end
end