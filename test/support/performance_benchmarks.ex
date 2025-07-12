defmodule PerformanceBenchmarks do
  @moduledoc """
  Performance benchmarks and baselines for MABEAM components.
  
  This module defines expected performance baselines for various MABEAM
  components to enable regression detection and performance monitoring.
  """
  
  # Agent performance baselines
  @agent_creation_baseline %{
    agents_per_second: 1000,
    memory_per_agent: 1024 * 1024,  # 1MB
    creation_time_ms: 1.0,
    min_creation_time_ms: 0.1,
    max_creation_time_ms: 10.0
  }
  
  @agent_action_baseline %{
    actions_per_second: 10000,
    average_execution_time_ms: 0.1,
    min_execution_time_ms: 0.01,
    max_execution_time_ms: 5.0,
    success_rate: 0.99
  }
  
  @agent_lifecycle_baseline %{
    cycles_per_second: 500,
    average_cycle_time_ms: 2.0,
    min_cycle_time_ms: 0.5,
    max_cycle_time_ms: 20.0,
    success_rate: 0.98
  }
  
  # System performance baselines
  @system_startup_baseline %{
    startup_time_ms: 100,
    component_initialization_ms: 50,
    ready_time_ms: 200,
    memory_overhead_mb: 10
  }
  
  @system_coordination_baseline %{
    coordination_latency_ms: 5.0,
    throughput_operations_per_sec: 1000,
    success_rate: 0.98,
    scalability_factor: 1.2
  }
  
  @system_load_baseline %{
    max_concurrent_agents: 1000,
    load_capacity_operations_per_sec: 5000,
    performance_degradation_threshold: 0.1,
    stability_score: 0.95
  }
  
  @system_memory_baseline %{
    memory_efficiency_ratio: 0.85,
    memory_scaling: :linear,
    max_memory_per_agent_mb: 1,
    memory_growth_rate_threshold: 0.05
  }
  
  # Event system baselines
  @event_system_baseline %{
    events_per_second: 10000,
    average_latency_ms: 1.0,
    min_latency_ms: 0.1,
    max_latency_ms: 10.0,
    propagation_efficiency: 0.95
  }
  
  @event_propagation_baseline %{
    subscribers_scaling_factor: 1.1,
    max_subscribers_tested: 1000,
    propagation_time_per_subscriber_ms: 0.01,
    pattern_matching_time_ms: 0.05
  }
  
  @event_stress_baseline %{
    sustained_event_rate: 8000,
    burst_event_rate: 15000,
    system_stability_threshold: 0.95,
    memory_stability_threshold: 0.9
  }
  
  # Registry performance baselines
  @registry_baseline %{
    lookup_time_ms: 0.1,
    register_time_ms: 0.5,
    unregister_time_ms: 0.5,
    concurrent_operations_per_sec: 5000
  }
  
  @registry_scalability_baseline %{
    scaling_factor: 1.2,
    performance_degradation_threshold: 0.15,
    max_tested_agents: 10000,
    memory_efficiency: 0.8
  }
  
  # Resource limit baselines
  @resource_limits_baseline %{
    process_limit_threshold: 0.9,
    memory_pressure_threshold_mb: 1000,
    recovery_time_ms: 1000,
    graceful_degradation_score: 0.8
  }
  
  @doc """
  Gets the baseline metrics for a specific component.
  
  ## Parameters
  
  - `component` - The component to get baselines for
  
  ## Returns
  
  - `map()` - The baseline metrics for the component
  
  ## Examples
  
      iex> PerformanceBenchmarks.get_baseline(:agent)
      %{agents_per_second: 1000, ...}
      
      iex> PerformanceBenchmarks.get_baseline(:event_system)
      %{events_per_second: 10000, ...}
  """
  @spec get_baseline(atom()) :: map()
  def get_baseline(component) do
    case component do
      :agent -> @agent_creation_baseline
      :agent_creation -> @agent_creation_baseline
      :agent_action -> @agent_action_baseline
      :agent_lifecycle -> @agent_lifecycle_baseline
      
      :system -> @system_startup_baseline
      :system_startup -> @system_startup_baseline
      :system_coordination -> @system_coordination_baseline
      :system_load -> @system_load_baseline
      :system_memory -> @system_memory_baseline
      
      :event_system -> @event_system_baseline
      :event_propagation -> @event_propagation_baseline
      :event_stress -> @event_stress_baseline
      
      :registry -> @registry_baseline
      :registry_scalability -> @registry_scalability_baseline
      
      :resource_limits -> @resource_limits_baseline
      
      _ -> %{}
    end
  end
  
  @doc """
  Gets all available baseline components.
  
  ## Returns
  
  - `list(atom())` - List of available components
  """
  @spec get_available_components() :: list(atom())
  def get_available_components do
    [
      :agent, :agent_creation, :agent_action, :agent_lifecycle,
      :system, :system_startup, :system_coordination, :system_load, :system_memory,
      :event_system, :event_propagation, :event_stress,
      :registry, :registry_scalability,
      :resource_limits
    ]
  end
  
  @doc """
  Checks if performance results meet baseline requirements.
  
  ## Parameters
  
  - `component` - The component being tested
  - `results` - The performance test results
  - `tolerance` - Acceptable deviation from baseline (default: 0.2 = 20%)
  
  ## Returns
  
  - `{:ok, analysis}` - Results meet baseline with analysis
  - `{:warning, analysis}` - Results close to baseline with warnings
  - `{:error, analysis}` - Results fail to meet baseline
  """
  @spec check_baseline_compliance(atom(), map(), float()) ::
    {:ok | :warning | :error, map()}
  def check_baseline_compliance(component, results, tolerance \\ 0.2) do
    baseline = get_baseline(component)
    
    if Enum.empty?(baseline) do
      {:error, %{reason: :no_baseline_available, component: component}}
    else
      analysis = analyze_against_baseline(baseline, results, tolerance)
      status = determine_compliance_status(analysis)
      
      {status, analysis}
    end
  end
  
  @doc """
  Compares two performance result sets for regression analysis.
  
  ## Parameters
  
  - `component` - The component being compared
  - `current_results` - Current performance results
  - `previous_results` - Previous performance results
  - `regression_threshold` - Threshold for regression detection (default: 0.1 = 10%)
  
  ## Returns
  
  - `map()` - Regression analysis results
  """
  @spec compare_performance_results(atom(), map(), map(), float()) :: map()
  def compare_performance_results(component, current_results, previous_results, regression_threshold \\ 0.1) do
    baseline = get_baseline(component)
    
    %{
      component: component,
      regression_analysis: detect_regressions(current_results, previous_results, regression_threshold),
      baseline_compliance: check_baseline_compliance(component, current_results),
      improvement_analysis: detect_improvements(current_results, previous_results),
      recommendations: generate_performance_recommendations(current_results, baseline)
    }
  end
  
  @doc """
  Generates a performance report card based on baseline compliance.
  
  ## Parameters
  
  - `component_results` - Map of component -> results
  
  ## Returns
  
  - `map()` - Performance report card
  """
  @spec generate_report_card(map()) :: map()
  def generate_report_card(component_results) do
    results = Enum.map(component_results, fn {component, results} ->
      {status, analysis} = check_baseline_compliance(component, results)
      
      {component, %{
        status: status,
        score: calculate_performance_score(analysis),
        analysis: analysis
      }}
    end)
    
    overall_score = calculate_overall_score(results)
    
    %{
      overall_score: overall_score,
      overall_status: determine_overall_status(overall_score),
      component_scores: Enum.into(results, %{}),
      summary: generate_summary(results),
      recommendations: generate_overall_recommendations(results)
    }
  end
  
  # Private helper functions
  
  defp analyze_against_baseline(baseline, results, tolerance) do
    comparisons = Enum.map(baseline, fn {metric, baseline_value} ->
      result_value = Map.get(results, metric, 0)
      
      deviation = calculate_deviation(baseline_value, result_value)
      status = determine_metric_status(metric, deviation, tolerance)
      
      {metric, %{
        baseline: baseline_value,
        actual: result_value,
        deviation: deviation,
        status: status
      }}
    end)
    
    Enum.into(comparisons, %{})
  end
  
  defp calculate_deviation(baseline, actual) when is_number(baseline) and is_number(actual) do
    if baseline != 0 do
      (actual - baseline) / baseline
    else
      if actual > 0, do: 1.0, else: 0.0
    end
  end
  
  defp calculate_deviation(_baseline, _actual), do: 0.0
  
  defp determine_metric_status(metric, deviation, tolerance) do
    # Metrics where higher values are better (throughput, rate, efficiency)
    higher_is_better = [
      :agents_per_second, :actions_per_second, :cycles_per_second,
      :events_per_second, :throughput_operations_per_sec, :load_capacity_operations_per_sec,
      :concurrent_operations_per_sec, :success_rate, :propagation_efficiency,
      :memory_efficiency_ratio, :stability_score, :memory_efficiency,
      :gc_effectiveness, :scalability_factor
    ]
    
    # Metrics where lower values are better (time, latency, memory usage)
    lower_is_better = [
      :creation_time_ms, :min_creation_time_ms, :max_creation_time_ms,
      :average_execution_time_ms, :min_execution_time_ms, :max_execution_time_ms,
      :average_cycle_time_ms, :min_cycle_time_ms, :max_cycle_time_ms,
      :average_latency_ms, :min_latency_ms, :max_latency_ms,
      :startup_time_ms, :component_initialization_ms, :ready_time_ms,
      :coordination_latency_ms, :lookup_time_ms, :register_time_ms, :unregister_time_ms,
      :propagation_time_per_subscriber_ms, :pattern_matching_time_ms,
      :memory_per_agent, :max_memory_per_agent_mb, :memory_overhead_mb,
      :performance_degradation_threshold, :memory_growth_rate_threshold,
      :recovery_time_ms
    ]
    
    cond do
      abs(deviation) <= tolerance ->
        :pass
      
      metric in higher_is_better ->
        if deviation > 0, do: :exceed, else: :fail
      
      metric in lower_is_better ->
        if deviation > 0, do: :fail, else: :exceed
      
      true ->
        # Default behavior for unknown metrics
        if deviation > tolerance, do: :fail, else: :exceed
    end
  end
  
  defp determine_compliance_status(analysis) do
    statuses = Enum.map(analysis, fn {_metric, data} -> data.status end)
    
    cond do
      Enum.all?(statuses, &(&1 in [:pass, :exceed])) -> :ok
      Enum.any?(statuses, &(&1 == :fail)) -> :error
      true -> :warning
    end
  end
  
  defp detect_regressions(current, previous, threshold) do
    common_metrics = Map.keys(current) |> Enum.filter(&Map.has_key?(previous, &1))
    
    regressions = Enum.filter(common_metrics, fn metric ->
      current_value = Map.get(current, metric, 0)
      previous_value = Map.get(previous, metric, 0)
      
      if is_number(current_value) and is_number(previous_value) and previous_value != 0 do
        regression_ratio = (current_value - previous_value) / previous_value
        regression_ratio > threshold
      else
        false
      end
    end)
    
    %{
      regressions_detected: !Enum.empty?(regressions),
      regressed_metrics: regressions,
      regression_count: length(regressions)
    }
  end
  
  defp detect_improvements(current, previous) do
    common_metrics = Map.keys(current) |> Enum.filter(&Map.has_key?(previous, &1))
    
    improvements = Enum.filter(common_metrics, fn metric ->
      current_value = Map.get(current, metric, 0)
      previous_value = Map.get(previous, metric, 0)
      
      # For most metrics, higher is better (like throughput)
      # For latency/time metrics, lower is better
      time_metrics = [:latency, :time, :duration]
      is_time_metric = Enum.any?(time_metrics, &String.contains?(to_string(metric), to_string(&1)))
      
      if is_time_metric do
        current_value < previous_value
      else
        current_value > previous_value
      end
    end)
    
    %{
      improvements_detected: !Enum.empty?(improvements),
      improved_metrics: improvements,
      improvement_count: length(improvements)
    }
  end
  
  defp generate_performance_recommendations(results, baseline) do
    recommendations = []
    
    # Add specific recommendations based on performance gaps
    recommendations = if Map.get(results, :memory_per_agent, 0) > Map.get(baseline, :memory_per_agent, 0) * 1.5 do
      ["Consider optimizing agent memory usage" | recommendations]
    else
      recommendations
    end
    
    recommendations = if Map.get(results, :success_rate, 1) < 0.95 do
      ["Investigate error rates and improve reliability" | recommendations]
    else
      recommendations
    end
    
    recommendations = if Map.get(results, :average_latency_ms, 0) > Map.get(baseline, :average_latency_ms, 0) * 2 do
      ["Focus on latency optimization" | recommendations]
    else
      recommendations
    end
    
    if Enum.empty?(recommendations) do
      ["Performance meets expectations"]
    else
      recommendations
    end
  end
  
  defp calculate_performance_score(analysis) do
    scores = Enum.map(analysis, fn {_metric, data} ->
      case data.status do
        :pass -> 1.0
        :exceed -> 1.2  # Better than baseline
        :fail -> 0.5
      end
    end)
    
    if Enum.empty?(scores) do
      0.0
    else
      Enum.sum(scores) / length(scores)
    end
  end
  
  defp calculate_overall_score(results) do
    scores = Enum.map(results, fn {_component, data} -> data.score end)
    
    if Enum.empty?(scores) do
      0.0
    else
      Enum.sum(scores) / length(scores)
    end
  end
  
  defp determine_overall_status(score) do
    cond do
      score >= 1.0 -> :excellent
      score >= 0.8 -> :good
      score >= 0.6 -> :acceptable
      score >= 0.4 -> :poor
      true -> :critical
    end
  end
  
  defp generate_summary(results) do
    total_components = length(results)
    excellent_count = Enum.count(results, fn {_comp, data} -> data.status == :ok end)
    warning_count = Enum.count(results, fn {_comp, data} -> data.status == :warning end)
    critical_count = Enum.count(results, fn {_comp, data} -> data.status == :error end)
    
    %{
      total_components: total_components,
      excellent_components: excellent_count,
      warning_components: warning_count,
      critical_components: critical_count,
      overall_health: cond do
        critical_count > 0 -> :critical
        warning_count > total_components / 2 -> :warning
        true -> :healthy
      end
    }
  end
  
  defp generate_overall_recommendations(results) do
    critical_components = Enum.filter(results, fn {_comp, data} -> data.status == :error end)
    
    if Enum.empty?(critical_components) do
      ["Overall performance is within acceptable ranges"]
    else
      critical_names = Enum.map(critical_components, fn {comp, _data} -> comp end)
      ["Critical performance issues in: #{Enum.join(critical_names, ", ")}"]
    end
  end
end