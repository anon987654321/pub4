# frozen_string_literal: true

require 'time'
require 'securerandom'

# Cognitive Orchestrator - Core 7±2 Working Memory Management
# Implements cognitive load monitoring with circuit breaker patterns
class CognitiveOrchestrator
  COMPLEXITY_THRESHOLDS = {
    simple: 1..2,
    moderate: 3..5,
    complex: 6..7,
    overload: 8..Float::INFINITY
  }.freeze

  CONCEPT_WEIGHTS = {
    basic_concept: 1.0,
    abstract_concept: 1.5,
    relationship: 1.2,
    nested_structure: 2.0,
    cross_domain_reference: 2.5
  }.freeze

  attr_reader :current_load, :concept_stack, :context_switches, :flow_state_indicators

  def initialize
    @current_load = 0
    @concept_stack = []
    @context_switches = 0
    @start_time = Time.now
    @flow_state_indicators = FlowStateTracker.new
    @circuit_breakers = {}
    @session_snapshots = {}
  end

  # Assess cognitive complexity of incoming content
  def assess_complexity(content)
    concepts = extract_concepts(content)
    relationships = extract_relationships(content)

    complexity_score = 0
    concepts.each do |concept|
      weight = determine_concept_weight(concept)
      complexity_score += weight
    end

    # Add relationship complexity
    complexity_score += relationships.size * CONCEPT_WEIGHTS[:relationship]

    complexity_score
  end

  # Check if system is experiencing cognitive overload
  def cognitive_overload?
    @current_load > 7 ||
      @concept_stack.length > 9 ||
      @context_switches > 3 ||
      @flow_state_indicators.distraction_level > 0.7
  end

  # Add concept to working memory with overflow protection
  def add_concept(concept, weight = 1.0)
    compress_working_memory if (@current_load + weight) > 7

    @concept_stack << {
      concept: concept,
      weight: weight,
      timestamp: Time.now,
      access_count: 1
    }

    @current_load += weight
    maintain_7_plus_minus_2_limit
  end

  # Context switch with cognitive load tracking
  def context_switch(new_context)
    @context_switches += 1

    trigger_cognitive_break if @context_switches > 3

    # Preserve current state
    snapshot_id = preserve_flow_state

    # Apply context compression
    compress_context(new_context)

    snapshot_id
  end

  # Trigger cognitive circuit breaker
  def trigger_circuit_breaker(session_data = {})
    puts '⚡ Cognitive overload detected. Triggering circuit breaker...'

    # Save current state
    snapshot = preserve_flow_state(session_data)

    # Reset cognitive load to manageable level
    @concept_stack = @concept_stack.last(3) # Keep only most recent concepts
    @current_load = 3
    @context_switches = 0

    # Schedule attention restoration
    schedule_attention_restoration(snapshot)

    snapshot[:id]
  end

  # Apply cognitive offloading strategies
  def apply_cognitive_offloading(snapshot)
    offloading_strategies = %i[
      compress_similar_concepts
      chunk_related_information
      create_concept_hierarchies
      preserve_attention_anchors
    ]

    offloading_strategies.each do |strategy|
      send(strategy, snapshot)
    end
  end

  # Get current cognitive state
  def cognitive_state
    {
      load: @current_load,
      complexity: determine_current_complexity,
      concepts: @concept_stack.size,
      switches: @context_switches,
      flow_state: @flow_state_indicators.current_state,
      overload_risk: overload_risk_percentage,
      timestamp: Time.now
    }
  end

  private

  # Extract concepts from content (simplified implementation)
  def extract_concepts(content)
    return [] unless content.is_a?(String)

    # Simple concept extraction - can be enhanced with NLP
    concepts = content.scan(/[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*/)
    concepts.uniq.map(&:strip)
  end

  # Extract relationships from content
  def extract_relationships(content)
    return [] unless content.is_a?(String)

    # Look for relationship indicators
    relationship_indicators = ['relates to', 'connects with', 'depends on', 'includes', 'extends']
    relationships = []

    relationship_indicators.each do |indicator|
      content.scan(/(\w+)\s+#{indicator}\s+(\w+)/i) do |match|
        relationships << { from: match[0], to: match[1], type: indicator }
      end
    end

    relationships
  end

  # Determine concept weight based on complexity
  def determine_concept_weight(concept)
    case concept.length
    when 0..5
      CONCEPT_WEIGHTS[:basic_concept]
    when 6..15
      CONCEPT_WEIGHTS[:abstract_concept]
    else
      CONCEPT_WEIGHTS[:nested_structure]
    end
  end

  # Maintain 7±2 concept limit in working memory
  def maintain_7_plus_minus_2_limit
    remove_least_accessed_concept while @concept_stack.size > 9
  end

  # Remove concept with lowest access count
  def remove_least_accessed_concept
    return if @concept_stack.empty?

    least_accessed = @concept_stack.min_by { |c| c[:access_count] }
    @concept_stack.delete(least_accessed)
    @current_load -= least_accessed[:weight]
  end

  # Compress working memory when approaching limits
  def compress_working_memory
    # Group similar concepts
    compressed_concepts = []
    remaining_concepts = @concept_stack.dup

    while remaining_concepts.any?
      concept = remaining_concepts.shift
      similar = remaining_concepts.select { |c| similar_concepts?(concept[:concept], c[:concept]) }

      if similar.any?
        # Create compressed concept group
        compressed_weight = ([concept] + similar).sum { |c| c[:weight] } * 0.6 # 40% compression
        compressed_concepts << {
          concept: "#{concept[:concept]} (compressed group)",
          weight: compressed_weight,
          timestamp: Time.now,
          access_count: 1,
          compressed: true
        }

        # Remove similar concepts from remaining
        similar.each { |s| remaining_concepts.delete(s) }
      else
        compressed_concepts << concept
      end
    end

    @concept_stack = compressed_concepts
    @current_load = @concept_stack.sum { |c| c[:weight] }
  end

  # Check if two concepts are similar (simple implementation)
  def similar_concepts?(concept1, concept2)
    # Simple similarity check - can be enhanced with semantic analysis
    concept1.downcase.include?(concept2.downcase) ||
      concept2.downcase.include?(concept1.downcase) ||
      concept1.split.any? { |word| concept2.split.include?(word) }
  end

  # Preserve current flow state
  def preserve_flow_state(session_data = {})
    snapshot_id = SecureRandom.hex(8)

    @session_snapshots[snapshot_id] = {
      id: snapshot_id,
      concepts: @concept_stack.dup,
      load: @current_load,
      switches: @context_switches,
      flow_state: @flow_state_indicators.current_state,
      session_data: session_data,
      timestamp: Time.now
    }

    snapshot_id
  end

  # Compress context for cognitive load management
  def compress_context(new_context)
    # Keep only essential concepts from new context
    essential_concepts = extract_essential_concepts(new_context)

    @concept_stack.clear
    @current_load = 0

    essential_concepts.each do |concept|
      add_concept(concept, CONCEPT_WEIGHTS[:basic_concept])
    end
  end

  # Extract essential concepts (top 3-5 most important)
  def extract_essential_concepts(context)
    all_concepts = extract_concepts(context.to_s)
    # Simple importance scoring - can be enhanced
    all_concepts.sort_by(&:length).reverse.take(5)
  end

  # Trigger cognitive break
  def trigger_cognitive_break
    puts '🧠 Cognitive break recommended. Context switching limit reached.'
    @context_switches = 0
  end

  # Schedule attention restoration
  def schedule_attention_restoration(snapshot)
    duration = calculate_break_duration
    restoration_type = determine_restoration_type

    puts "🌱 Scheduling #{restoration_type} restoration for #{duration} seconds"
    puts "   Snapshot ID: #{snapshot[:id]} preserved for restoration"
  end

  # Calculate optimal break duration
  def calculate_break_duration
    base_duration = 30 # 30 seconds base
    load_multiplier = [@current_load / 7.0, 1.0].max

    (base_duration * load_multiplier).round
  end

  # Determine restoration type based on cognitive state
  def determine_restoration_type
    case @current_load
    when 0..3
      :brief_pause
    when 4..6
      :context_refresh
    else
      :deep_restoration
    end
  end

  # Determine current complexity level
  def determine_current_complexity
    case @current_load
    when COMPLEXITY_THRESHOLDS[:simple]
      :simple
    when COMPLEXITY_THRESHOLDS[:moderate]
      :moderate
    when COMPLEXITY_THRESHOLDS[:complex]
      :complex
    else
      :overload
    end
  end

  # Calculate overload risk percentage
  def overload_risk_percentage
    [@current_load / 7.0 * 100, 100].min.round(1)
  end

  # Cognitive offloading strategies
  def compress_similar_concepts(snapshot)
    # Implementation for compressing similar concepts
  end

  def chunk_related_information(snapshot)
    # Implementation for chunking related information
  end

  def create_concept_hierarchies(snapshot)
    # Implementation for creating concept hierarchies
  end

  def preserve_attention_anchors(snapshot)
    # Implementation for preserving attention anchors
  end
end

# Flow State Tracker for cognitive monitoring
class FlowStateTracker
  attr_reader :current_state, :distraction_level

  def initialize
    @current_state = :optimal
    @distraction_level = 0.0
    @state_history = []
  end

  def update_state(indicators)
    # Update based on various indicators
    @distraction_level = calculate_distraction(indicators)
    @current_state = determine_flow_state(@distraction_level)

    @state_history << {
      state: @current_state,
      distraction: @distraction_level,
      timestamp: Time.now
    }

    # Keep only recent history
    @state_history = @state_history.last(10)
  end

  private

  def calculate_distraction(indicators)
    # Simple distraction calculation
    distraction = 0.0
    distraction += indicators[:context_switches] * 0.2 if indicators[:context_switches]
    distraction += indicators[:error_rate] if indicators[:error_rate]
    distraction += indicators[:response_time_deviation] if indicators[:response_time_deviation]

    [distraction, 1.0].min
  end

  def determine_flow_state(distraction)
    case distraction
    when 0.0..0.2
      :optimal
    when 0.2..0.5
      :focused
    when 0.5..0.7
      :stressed
    else
      :overloaded
    end
  end
end
