# frozen_string_literal: true

module MASTER
  # Enforces gate conditions for each development phase.
  # A phase cannot complete until all its gates pass.
  module PhaseGates
    PHASES = {
      discover:   { gates: [:no_vague_words, :success_measurable] },
      analyze:    { gates: [:components_distinct] },
      ideate:     { gates: [:count_gte_15] },
      design:     { gates: [:interfaces_explicit] },
      implement:  { gates: [:zero_violations] },
      validate:   { gates: [:zero_test_failures] },
      deliver:    { gates: [:deployed] },
    }.freeze

    module_function

    def check(phase, context = {})
      phase_def = PHASES[phase.to_sym]
      return Result.ok("no gates defined") unless phase_def

      failed = phase_def[:gates].reject { |gate| pass?(gate, context) }
      return Result.ok("all gates passed") if failed.empty?

      Result.err("Phase #{phase} gate(s) not met: #{failed.join(", ")}")
    end

    def pass?(gate, context)
      case gate
      when :zero_violations  then context[:violation_count].to_i.zero?
      when :count_gte_15     then context[:alternative_count].to_i >= 15
      when :zero_test_failures then context[:test_failures].to_i.zero?
      when :no_vague_words
        text = context[:problem_statement].to_s
        !text.match?(/\b(somehow|something|maybe|kind of|sort of|whatever)\b/i)
      when :success_measurable
        context[:success_criteria].to_s.length > 10
      else true  # unknown gates pass by default
      end
    end
  end
end
