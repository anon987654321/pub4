# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Rule health and enforcement mode assessment. Identifies noisy detectors
      # and demotes them to measurement-only mode so they inform but don't block.
      # A rule with known false-positive rate above threshold becomes advisory.
      module RuleHealth
        module_function

        # Rules with documented high false-positive rates. Each fires on patterns
        # that are valid code by design but the rule's detector misfires.
        NOISY_RULE_IDS = %w[
          CQS
          MAGIC_COLOR
          DOUBLE_QUOTES_RUBY
        ].freeze

        # Rule is in measurement-only mode: visible but non-blocking.
        def measurement_mode?(rule)
          return false unless rule.respond_to?(:id)

          id = rule.id.to_s
          NOISY_RULE_IDS.include?(id) || (rule.respond_to?(:measurement_mode) && rule.measurement_mode == true)
        end

        # Enforcement level for this rule: :blocking, :advisory, or :measurement.
        def enforcement(rule)
          if measurement_mode?(rule)
            :measurement
          elsif rule.respond_to?(:severity)
            case rule.severity.to_s
            when "error", "critical", "veto"
              :blocking
            else
              :advisory
            end
          else
            :advisory
          end
        end

        # User-facing description of the rule's enforcement mode.
        def user_message(rule)
          case enforcement(rule)
          when :measurement
            "#{rule.id}: measured only — non-blocking, known false-positive profile"
          when :blocking
            "#{rule.id}: blocking rule"
          else
            "#{rule.id}: advisory finding"
          end
        end

        # Calibration metadata for this rule from the law.
        def calibration(rule)
          return {} unless rule.respond_to?(:id)

          id = rule.id.to_s
          {
            "measurement_mode" => measurement_mode?(rule),
            "enforcement" => enforcement(rule).to_s,
            "known_noisy" => NOISY_RULE_IDS.include?(id)
          }
        end
      end
    end
  end
end
