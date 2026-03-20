# frozen_string_literal: true

module Master
  # Tracks cognitive load of agent sessions using 7±2 working memory model.
  # Ported from pub/ai3/lib/cognitive_orchestrator.rb, adapted for MASTER.
  class CognitiveMonitor
    # LOAD_MAX and STACK_MAX are derived from Miller's Law (1956): humans hold
    # 7±2 chunks in working memory. LOAD_MAX=7 is the mean; STACK_MAX=9 is the upper bound.
    LOAD_MAX    = 7
    STACK_MAX   = 9
    SWITCH_MAX  = 3
    COMPRESS_AT = 0.6  # 40% compression ratio

    FLOW_STATES = {
      optimal:    0.0..0.2,
      focused:    0.2..0.5,
      stressed:   0.5..0.7,
      overloaded: 0.7..Float::INFINITY
    }.freeze

    attr_reader :load, :switches, :flow_state

    def initialize
      @load      = 0.0
      @stack     = []   # [{concept:, weight:, ts:}]
      @switches  = 0
      @flow_state = :optimal
    end

    def push(concept, weight: 1.0)
      compress! if (@load + weight) > LOAD_MAX
      @stack << { concept: concept, weight: weight, ts: Time.now.to_i }
      @load += weight
      evict_excess!
      self
    end

    def context_switch!
      @switches += 1
      reset_switches! if @switches > SWITCH_MAX
      self
    end

    def overloaded?
      @load > LOAD_MAX || @stack.size > STACK_MAX || @switches > SWITCH_MAX
    end

    def reset!(keep_recent: 3)
      @stack     = @stack.last(keep_recent)
      @load      = @stack.sum { |c| c[:weight] }
      @switches  = 0
      @flow_state = :focused
      self
    end

    def state
      {
        load: @load.round(2),
        stack_size: @stack.size,
        switches: @switches,
        flow_state: @flow_state,
        overload_risk: [(@load / LOAD_MAX * 100), 100].min.round(1),
        complexity: complexity_label
      }
    end

    def update_flow(context_switches: @switches, error_rate: 0.0)
      distraction = [context_switches * 0.2 + error_rate, 1.0].min
      @flow_state = FLOW_STATES.find { |_, range| range.cover?(distraction) }&.first || :overloaded
      self
    end

    private

    def compress!
      grouped = @stack.group_by { |c| c[:concept][0..4] }
      @stack = grouped.map do |_, group|
        total = group.sum { |c| c[:weight] } * COMPRESS_AT
        { concept: "#{group.first[:concept]}[×#{group.size}]", weight: total, ts: Time.now.to_i }
      end
      @load = @stack.sum { |c| c[:weight] }
    end

    def evict_excess!
      @stack.shift while @stack.size > STACK_MAX
      @load = @stack.sum { |c| c[:weight] }
    end

    def reset_switches!
      @switches  = 0
      @flow_state = :focused
    end

    def complexity_label
      case @load
      when 0..2   then :simple
      when 2..5   then :moderate
      when 5..7   then :complex
      else             :overload
      end
    end
  end
end