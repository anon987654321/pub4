# frozen_string_literal: true

require_relative 'cognitive_orchestrator'
require 'yaml'

# Base Assistant Framework with Cognitive Profile Integration
class BaseAssistant
  attr_reader :name, :role, :capabilities, :cognitive_profile, :session_context

  def initialize(name, config = {})
    @name = name
    @config = config
    @role = config['role'] || 'General Assistant'
    @capabilities = config['capabilities'] || []
    @cognitive_profile = CognitiveProfile.new(name, config['cognitive_settings'] || {})
    @session_context = {}
    @response_cache = {}
    @tools = initialize_tools
  end

  # Main response method with cognitive integration
  def respond(input, context: {})
    # Cognitive load assessment
    complexity = @cognitive_profile.assess_input_complexity(input)

    return simplify_and_respond(input, context) if complexity > @cognitive_profile.max_cognitive_load

    # Context-aware response generation
    enhanced_context = merge_contexts(context, @session_context)
    response = generate_response(input, enhanced_context)

    # Update session context with new information
    update_session_context(input, response)

    response
  end

  # Generate response (to be overridden by specific assistants)
  def generate_response(input, _context)
    "I'm #{@name}, a #{@role}. I received: #{input}"
  end

  # Simplified response for high cognitive load
  def simplify_and_respond(input, context)
    # Reduce complexity by focusing on key elements
    simplified_input = extract_key_intent(input)
    simplified_context = compress_context(context)

    "🧠 Simplified response: #{generate_response(simplified_input, simplified_context)}"
  end

  # Check if assistant can handle the request
  def can_handle?(input, _context = {})
    # Basic capability matching
    input_lower = input.to_s.downcase
    @capabilities.any? { |cap| input_lower.include?(cap.downcase) }
  end

  # Get assistant status
  def status
    {
      name: @name,
      role: @role,
      capabilities: @capabilities,
      cognitive_load: @cognitive_profile.current_load,
      flow_state: @cognitive_profile.flow_state,
      session_active: !@session_context.empty?
    }
  end

  protected

  # Initialize available tools
  def initialize_tools
    tools = {}

    tools[:rag] = true if @config['tools']&.include?('rag')

    tools[:web_scraping] = true if @config['tools']&.include?('web_scraping')

    tools[:file_access] = true if @config['tools']&.include?('file_access')

    tools
  end

  # Merge different context sources
  def merge_contexts(new_context, session_context)
    merged = session_context.dup
    merged.merge!(new_context) if new_context.is_a?(Hash)
    merged
  end

  # Update session context
  def update_session_context(input, response)
    @session_context[:last_input] = input
    @session_context[:last_response] = response
    @session_context[:updated_at] = Time.now

    # Apply cognitive load to profile
    @cognitive_profile.add_interaction(input, response)
  end

  # Extract key intent from complex input
  def extract_key_intent(input)
    # Simple intent extraction - can be enhanced with NLP
    sentences = input.to_s.split(/[.!?]/)
    key_sentence = sentences.max_by(&:length) || input.to_s
    key_sentence.strip
  end

  # Compress context for cognitive load management
  def compress_context(context)
    return {} unless context.is_a?(Hash)

    # Keep only essential keys
    essential_keys = %i[user_intent domain priority previous_action]
    compressed = {}

    essential_keys.each do |key|
      compressed[key] = context[key] if context.key?(key)
    end

    compressed
  end
end

# Cognitive Profile for individual assistants
class CognitiveProfile
  attr_reader :name, :current_load, :max_cognitive_load, :flow_state, :interaction_history

  def initialize(name, settings = {})
    @name = name
    @max_cognitive_load = settings['max_cognitive_load'] || 7
    @current_load = 0
    @flow_state = :optimal
    @interaction_history = []
    @complexity_weights = settings['complexity_weights'] || default_complexity_weights
  end

  # Assess input complexity
  def assess_input_complexity(input)
    complexity = 0
    text = input.to_s

    # Word count factor
    word_count = text.split.size
    complexity += (word_count / 50.0) * @complexity_weights[:word_count]

    # Question complexity
    question_count = text.count('?')
    complexity += question_count * @complexity_weights[:questions]

    # Technical terms
    technical_patterns = %w[implement algorithm architecture framework system]
    technical_count = technical_patterns.count { |pattern| text.downcase.include?(pattern) }
    complexity += technical_count * @complexity_weights[:technical_terms]

    # Request complexity
    request_patterns = %w[analyze compare evaluate design create]
    request_count = request_patterns.count { |pattern| text.downcase.include?(pattern) }
    complexity += request_count * @complexity_weights[:complex_requests]

    complexity
  end

  # Add interaction to profile
  def add_interaction(input, _response)
    complexity = assess_input_complexity(input)
    @current_load += complexity * 0.1 # Gradual load increase

    # Apply cognitive decay
    @current_load *= 0.95 if @current_load > 0

    # Update flow state
    update_flow_state

    # Record interaction
    @interaction_history << {
      input_complexity: complexity,
      cognitive_load: @current_load,
      flow_state: @flow_state,
      timestamp: Time.now
    }

    # Keep history manageable
    @interaction_history = @interaction_history.last(20)
  end

  # Reset cognitive state
  def reset_cognitive_state
    @current_load = 0
    @flow_state = :optimal
    @interaction_history.clear
  end

  # Get cognitive insights
  def cognitive_insights
    return {} if @interaction_history.empty?

    recent_interactions = @interaction_history.last(10)
    avg_complexity = recent_interactions.sum { |i| i[:input_complexity] } / recent_interactions.size
    avg_load = recent_interactions.sum { |i| i[:cognitive_load] } / recent_interactions.size

    {
      average_complexity: avg_complexity.round(2),
      average_load: avg_load.round(2),
      current_load: @current_load.round(2),
      flow_state: @flow_state,
      interactions_count: @interaction_history.size,
      overload_events: @interaction_history.count { |i| i[:cognitive_load] > @max_cognitive_load }
    }
  end

  private

  def default_complexity_weights
    {
      word_count: 1.0,
      questions: 1.5,
      technical_terms: 2.0,
      complex_requests: 2.5
    }
  end

  def update_flow_state
    @flow_state = case @current_load
                  when 0..2
                    :optimal
                  when 3..5
                    :focused
                  when 6..7
                    :challenged
                  else
                    :overloaded
                  end
  end
end

# Assistant Registry for managing all assistants
class AssistantRegistry
  attr_reader :assistants, :cognitive_orchestrator

  def initialize(cognitive_orchestrator = nil)
    @assistants = {}
    @cognitive_orchestrator = cognitive_orchestrator
    @load_balancer = LoadBalancer.new
    @assistant_configs = load_assistant_configs

    initialize_default_assistants
  end

  # Register new assistant
  def register_assistant(name, assistant_class, config = {})
    assistant = assistant_class.new(name, config)
    @assistants[name.to_sym] = assistant
    puts "📝 Registered assistant: #{name} (#{assistant.role})"
  end

  # Get assistant by name
  def get_assistant(name)
    @assistants[name.to_sym]
  end

  # Find best assistant for query
  def find_best_assistant(query, context = {})
    candidates = @assistants.values.select { |assistant| assistant.can_handle?(query, context) }

    if candidates.empty?
      return @assistants[:general] # Fallback to general assistant
    end

    # Use load balancer to select best assistant
    @load_balancer.select_best_assistant(candidates, query, context)
  end

  # List all assistants
  def list_assistants
    @assistants.map do |name, assistant|
      {
        name: name,
        role: assistant.role,
        capabilities: assistant.capabilities,
        status: assistant.status
      }
    end
  end

  # Get registry statistics
  def statistics
    total_assistants = @assistants.size
    active_assistants = @assistants.count { |_, a| !a.session_context.empty? }

    cognitive_loads = @assistants.values.map { |a| a.cognitive_profile.current_load }
    avg_cognitive_load = cognitive_loads.empty? ? 0 : cognitive_loads.sum / cognitive_loads.size

    {
      total_assistants: total_assistants,
      active_assistants: active_assistants,
      average_cognitive_load: avg_cognitive_load.round(2),
      registry_health: determine_registry_health(avg_cognitive_load)
    }
  end

  # Reset all assistants
  def reset_all_assistants
    @assistants.each_value { |assistant| assistant.cognitive_profile.reset_cognitive_state }
    puts '🔄 Reset all assistant cognitive states'
  end

  private

  # Load assistant configurations
  def load_assistant_configs
    config_file = 'config/assistants.yml'
    return {} unless File.exist?(config_file)

    YAML.load_file(config_file) || {}
  rescue StandardError
    {}
  end

  # Initialize default assistants
  def initialize_default_assistants
    # General assistant (always available)
    register_assistant('general', BaseAssistant, {
                         'role' => 'General Purpose Assistant',
                         'capabilities' => %w[general help information],
                         'tools' => ['rag']
                       })

    # Load additional assistants from config
    @assistant_configs.each do |name, config|
      assistant_class = Object.const_get("#{name.capitalize}Assistant")
      register_assistant(name, assistant_class, config)
    rescue NameError
      puts "⚠️ Assistant class #{name.capitalize}Assistant not found, using BaseAssistant"
      register_assistant(name, BaseAssistant, config)
    end
  end

  def determine_registry_health(avg_load)
    case avg_load
    when 0..3
      'excellent'
    when 3..5
      'good'
    when 5..7
      'fair'
    else
      'overloaded'
    end
  end
end

# Load Balancer for assistant selection
class LoadBalancer
  def initialize
    @selection_history = []
  end

  # Select best assistant based on multiple factors
  def select_best_assistant(candidates, query, context)
    return candidates.first if candidates.size == 1

    # Score each candidate
    scored_candidates = candidates.map do |assistant|
      score = calculate_assistant_score(assistant, query, context)
      { assistant: assistant, score: score }
    end

    # Select highest scoring assistant
    best_candidate = scored_candidates.max_by { |c| c[:score] }

    # Record selection
    @selection_history << {
      query: query[0..100],
      selected: best_candidate[:assistant].name,
      score: best_candidate[:score],
      timestamp: Time.now
    }

    # Keep history manageable
    @selection_history = @selection_history.last(50)

    best_candidate[:assistant]
  end

  private

  def calculate_assistant_score(assistant, query, context)
    score = 0

    # Capability matching (40% weight)
    capability_score = calculate_capability_score(assistant, query)
    score += capability_score * 0.4

    # Cognitive load (30% weight) - prefer less loaded assistants
    cognitive_score = (7 - assistant.cognitive_profile.current_load) / 7.0
    score += cognitive_score * 0.3

    # Recent usage (20% weight) - distribute load
    usage_score = calculate_usage_score(assistant)
    score += usage_score * 0.2

    # Context relevance (10% weight)
    context_score = calculate_context_score(assistant, context)
    score += context_score * 0.1

    score
  end

  def calculate_capability_score(assistant, query)
    query_lower = query.to_s.downcase
    matching_capabilities = assistant.capabilities.count do |cap|
      query_lower.include?(cap.downcase)
    end

    return 0 if assistant.capabilities.empty?

    matching_capabilities.to_f / assistant.capabilities.size
  end

  def calculate_usage_score(assistant)
    recent_selections = @selection_history.last(10)
    usage_count = recent_selections.count { |s| s[:selected] == assistant.name }

    # Prefer less recently used assistants
    1.0 - (usage_count / 10.0)
  end

  def calculate_context_score(assistant, context)
    # Simple context matching
    return 0.5 unless context.is_a?(Hash) && context[:domain]

    domain = context[:domain].to_s.downcase
    assistant.capabilities.any? { |cap| cap.downcase.include?(domain) } ? 1.0 : 0.0
  end
end
