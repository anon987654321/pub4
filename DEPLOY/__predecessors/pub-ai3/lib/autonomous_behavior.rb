# frozen_string_literal: true

require_relative 'multi_llm_manager'
require_relative 'cognitive_orchestrator'

# Autonomous Behavior System - Enhanced AI³ Component
# Handles task prioritization, dynamic queue management, and performance optimization
class AutonomousBehavior
  attr_accessor :tasks, :performance_metrics, :llm_manager, :cognitive_orchestrator

  def initialize
    @tasks = []
    @performance_metrics = {
      tasks_completed: 0,
      avg_completion_time: 0,
      success_rate: 0.0,
      cognitive_efficiency: 0.0
    }
    @llm_manager = MultiLLMManager.new
    @cognitive_orchestrator = CognitiveOrchestrator.new
    @task_history = []
  end

  # Add task to queue with intelligent prioritization
  def add_task(description, urgency: 3, feedback_score: 0, metadata: {})
    task = {
      id: generate_task_id,
      description: description,
      urgency: urgency,
      feedback_score: feedback_score,
      created_at: Time.now,
      status: :pending,
      metadata: metadata,
      priority: calculate_priority(urgency, feedback_score, metadata)
    }

    @tasks << task
    puts "🤖 Added task: #{description} (Priority: #{task[:priority]})"
    
    # Auto-trigger prioritization if queue is getting large
    prioritize_tasks if @tasks.size > 5
    
    task
  end

  # Dynamic task queue management with intelligent prioritization
  def prioritize_tasks
    puts '🧠 Prioritizing tasks based on feedback, urgency, and cognitive load...'
    
    # Sort by priority score (higher = more important)
    @tasks.sort_by! { |task| -task[:priority] }
    
    # Cognitive load balancing - spread high-cognitive tasks
    balance_cognitive_load
    
    puts "📊 Task queue reordered: #{@tasks.map { |t| t[:description][0..30] }}"
    
    # Execute highest priority tasks
    execute_ready_tasks
  end

  # Execute tasks that are ready based on dependencies and cognitive capacity
  def execute_ready_tasks
    available_cognitive_capacity = @cognitive_orchestrator.available_capacity
    
    @tasks.select { |t| t[:status] == :pending }.each do |task|
      break if available_cognitive_capacity <= 0
      
      cognitive_cost = estimate_cognitive_cost(task)
      if cognitive_cost <= available_cognitive_capacity
        execute_task(task)
        available_cognitive_capacity -= cognitive_cost
      end
    end
  end

  # Performance optimization automation
  def optimize_performance
    puts '⚡ Running performance optimization...'
    
    # Analyze task completion patterns
    analyze_performance_patterns
    
    # Optimize LLM selection based on task types
    optimize_llm_selection
    
    # Adjust cognitive load thresholds
    adjust_cognitive_thresholds
    
    # Clean up completed tasks older than 24 hours
    cleanup_old_tasks
    
    puts "✨ Performance optimization complete. Efficiency: #{@performance_metrics[:cognitive_efficiency]}%"
  end

  # Update LLM interface capabilities
  def update_llm_interface
    puts '🔄 Updating LLM interface capabilities...'
    
    # Query available models and capabilities
    available_models = @llm_manager.get_available_models
    
    # Update model capabilities based on recent performance
    available_models.each do |model|
      performance_data = get_model_performance(model)
      @llm_manager.update_model_capabilities(model, performance_data)
    end
    
    # Rebalance model selection weights
    @llm_manager.rebalance_selection_weights(@performance_metrics)
    
    puts "🚀 LLM interface updated with #{available_models.size} models"
  end

  # Get current queue status
  def queue_status
    {
      total_tasks: @tasks.size,
      pending: @tasks.count { |t| t[:status] == :pending },
      in_progress: @tasks.count { |t| t[:status] == :in_progress },
      completed: @tasks.count { |t| t[:status] == :completed },
      failed: @tasks.count { |t| t[:status] == :failed },
      average_priority: @tasks.empty? ? 0 : @tasks.sum { |t| t[:priority] }.to_f / @tasks.size
    }
  end

  # Get performance metrics
  def get_performance_metrics
    @performance_metrics.merge(
      queue_status: queue_status,
      cognitive_load: @cognitive_orchestrator.current_load,
      task_completion_rate: calculate_completion_rate
    )
  end

  private

  # Generate unique task ID
  def generate_task_id
    "task_#{Time.now.to_i}_#{rand(1000)}"
  end

  # Calculate task priority based on multiple factors
  def calculate_priority(urgency, feedback_score, metadata)
    base_priority = urgency * 10
    feedback_bonus = feedback_score * 5
    
    # Time-based urgency decay
    time_factor = metadata[:deadline] ? calculate_deadline_urgency(metadata[:deadline]) : 0
    
    # Resource availability factor
    resource_factor = @cognitive_orchestrator.available_capacity * 2
    
    [base_priority + feedback_bonus + time_factor + resource_factor, 100].min
  end

  # Calculate deadline urgency factor
  def calculate_deadline_urgency(deadline)
    return 0 unless deadline.is_a?(Time)
    
    time_remaining = deadline - Time.now
    return 50 if time_remaining <= 0  # Overdue tasks get high urgency
    
    # Urgency increases as deadline approaches
    case time_remaining
    when 0..3600      then 40  # 1 hour
    when 3600..14400  then 25  # 4 hours
    when 14400..86400 then 10  # 24 hours
    else 5
    end
  end

  # Balance cognitive load across task queue
  def balance_cognitive_load
    high_cognitive_tasks = @tasks.select { |t| estimate_cognitive_cost(t) > 5 }
    
    # Intersperse high-cognitive tasks with lighter ones
    if high_cognitive_tasks.size > @tasks.size / 3
      puts '🧠 Balancing cognitive load distribution'
      
      light_tasks = @tasks - high_cognitive_tasks
      balanced_queue = []
      
      high_cognitive_tasks.each_with_index do |task, index|
        balanced_queue << task
        balanced_queue << light_tasks[index] if light_tasks[index]
      end
      
      @tasks = balanced_queue + light_tasks[high_cognitive_tasks.size..-1].to_a
    end
  end

  # Estimate cognitive cost of a task
  def estimate_cognitive_cost(task)
    base_cost = case task[:description].downcase
                when /optimize|analyze|complex/ then 7
                when /update|modify|enhance/ then 5
                when /simple|basic|quick/ then 2
                else 4
                end
    
    # Adjust based on metadata
    metadata_multiplier = task[:metadata][:complexity_factor] || 1.0
    (base_cost * metadata_multiplier).round
  end

  # Execute a specific task
  def execute_task(task)
    start_time = Time.now
    task[:status] = :in_progress
    task[:started_at] = start_time
    
    puts "🚀 Executing task: #{task[:description]}"
    
    begin
      result = perform_task_action(task)
      task[:status] = :completed
      task[:completed_at] = Time.now
      task[:result] = result
      
      # Update performance metrics
      completion_time = Time.now - start_time
      update_performance_metrics(task, completion_time, true)
      
      puts "✅ Task completed: #{task[:description]} (#{completion_time.round(2)}s)"
      
    rescue StandardError => e
      task[:status] = :failed
      task[:error] = e.message
      task[:failed_at] = Time.now
      
      update_performance_metrics(task, Time.now - start_time, false)
      puts "❌ Task failed: #{task[:description]} - #{e.message}"
    end
    
    # Move to history if completed or failed
    if [:completed, :failed].include?(task[:status])
      @task_history << @tasks.delete(task)
    end
  end

  # Perform the actual task action
  def perform_task_action(task)
    case task[:description].downcase
    when /optimize performance/
      optimize_system_performance
    when /improve accuracy/
      improve_model_accuracy
    when /update llm/
      update_llm_interface
    when /analyze/
      perform_analysis(task[:metadata])
    when /enhance/
      perform_enhancement(task[:metadata])
    else
      # Generic task execution using LLM
      @llm_manager.process_request(
        "Perform the following task: #{task[:description]}",
        context: task[:metadata]
      )
    end
  end

  # Optimize system performance
  def optimize_system_performance
    # Garbage collection
    GC.start
    
    # Clear old cached data
    @llm_manager.clear_old_cache
    @cognitive_orchestrator.optimize_memory
    
    # Defragment task queue
    @tasks.compact!
    
    'System performance optimized'
  end

  # Improve model accuracy based on feedback
  def improve_model_accuracy
    feedback_data = @task_history.select { |t| t[:feedback_score] }
    
    if feedback_data.any?
      avg_feedback = feedback_data.sum { |t| t[:feedback_score] }.to_f / feedback_data.size
      @llm_manager.adjust_model_weights_based_on_feedback(avg_feedback)
      
      "Model accuracy improved based on #{feedback_data.size} feedback samples"
    else
      'No feedback data available for accuracy improvement'
    end
  end

  # Perform analysis task
  def perform_analysis(metadata)
    target = metadata[:target] || 'system performance'
    @cognitive_orchestrator.analyze(target)
  end

  # Perform enhancement task
  def perform_enhancement(metadata)
    component = metadata[:component] || 'general system'
    "Enhanced #{component} with improved capabilities"
  end

  # Update performance metrics
  def update_performance_metrics(task, completion_time, success)
    @performance_metrics[:tasks_completed] += 1
    
    # Update average completion time
    current_avg = @performance_metrics[:avg_completion_time]
    task_count = @performance_metrics[:tasks_completed]
    @performance_metrics[:avg_completion_time] = (current_avg * (task_count - 1) + completion_time) / task_count
    
    # Update success rate
    successful_tasks = @task_history.count { |t| t[:status] == :completed } + (success ? 1 : 0)
    @performance_metrics[:success_rate] = (successful_tasks.to_f / task_count * 100).round(2)
    
    # Update cognitive efficiency
    cognitive_cost = estimate_cognitive_cost(task)
    if success && completion_time > 0
      efficiency = (cognitive_cost / completion_time * 10).round(2)
      current_eff = @performance_metrics[:cognitive_efficiency]
      @performance_metrics[:cognitive_efficiency] = (current_eff * 0.9 + efficiency * 0.1).round(2)
    end
  end

  # Analyze performance patterns
  def analyze_performance_patterns
    return if @task_history.size < 5
    
    # Find most efficient task types
    task_types = @task_history.group_by { |t| t[:description].split.first.downcase }
    task_types.each do |type, tasks|
      avg_time = tasks.sum { |t| (t[:completed_at] - t[:started_at]) rescue 0 } / tasks.size
      success_rate = tasks.count { |t| t[:status] == :completed }.to_f / tasks.size
      
      puts "📈 #{type.capitalize}: avg #{avg_time.round(2)}s, #{(success_rate * 100).round}% success"
    end
  end

  # Optimize LLM selection based on task performance
  def optimize_llm_selection
    task_performance_by_model = {}
    
    @task_history.each do |task|
      model = task[:metadata][:model_used]
      next unless model
      
      task_performance_by_model[model] ||= { count: 0, success: 0, avg_time: 0 }
      task_performance_by_model[model][:count] += 1
      task_performance_by_model[model][:success] += 1 if task[:status] == :completed
      
      if task[:completed_at] && task[:started_at]
        time = task[:completed_at] - task[:started_at]
        current_avg = task_performance_by_model[model][:avg_time]
        count = task_performance_by_model[model][:count]
        task_performance_by_model[model][:avg_time] = (current_avg * (count - 1) + time) / count
      end
    end
    
    # Update LLM manager with performance data
    task_performance_by_model.each do |model, stats|
      @llm_manager.update_model_performance(model, stats)
    end
  end

  # Adjust cognitive thresholds based on performance
  def adjust_cognitive_thresholds
    if @performance_metrics[:success_rate] > 90
      @cognitive_orchestrator.increase_capacity_threshold(0.1)
    elsif @performance_metrics[:success_rate] < 70
      @cognitive_orchestrator.decrease_capacity_threshold(0.1)
    end
  end

  # Clean up old completed tasks
  def cleanup_old_tasks
    cutoff_time = Time.now - (24 * 3600) # 24 hours ago
    
    old_tasks = @task_history.select do |task|
      (task[:completed_at] || task[:failed_at] || task[:created_at]) < cutoff_time
    end
    
    @task_history -= old_tasks
    puts "🧹 Cleaned up #{old_tasks.size} old tasks"
  end

  # Get model performance data
  def get_model_performance(model)
    model_tasks = @task_history.select { |t| t[:metadata][:model_used] == model }
    return {} if model_tasks.empty?
    
    {
      total_tasks: model_tasks.size,
      success_rate: model_tasks.count { |t| t[:status] == :completed }.to_f / model_tasks.size,
      avg_completion_time: model_tasks.sum { |t| 
        (t[:completed_at] - t[:started_at]) rescue 0 
      } / model_tasks.size
    }
  end

  # Calculate overall task completion rate
  def calculate_completion_rate
    return 0.0 if @task_history.empty?
    
    completed = @task_history.count { |t| t[:status] == :completed }
    (completed.to_f / @task_history.size * 100).round(2)
  end
end