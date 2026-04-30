# frozen_string_literal: true

module MASTER
  # Resolves conflicts when multiple principles give opposing advice.
  # Rules mirror master.yml conflicts section.
  module ConflictResolver
    RULES = [
      {
        condition: ->(ids) { ids.include?(16) && (ids.include?(17) || ids.include?(18)) },
        resolution: "Favor WET/AHA (17/18) over DRY (16) when fewer than 3 duplications exist",
        prefer: [17, 18],
        suppress: [16],
      },
      {
        condition: ->(ids) { ids.include?(1) && ids.include?(2) },
        resolution: "Favor Clarity (1) over Simplicity (2) when they conflict",
        prefer: [1],
        suppress: [2],
      },
    ].freeze

    module_function

    # Given a list of violations (each with :principle_id), resolve conflicts.
    # Returns filtered list with suppressed violations removed and resolution notes added.
    def resolve(violations)
      ids = violations.map { |v| v[:principle_id].to_i }

      RULES.each do |rule|
        next unless rule[:condition].call(ids)
        violations = violations.reject { |v| rule[:suppress].include?(v[:principle_id].to_i) }
        violations = violations.map do |v|
          rule[:prefer].include?(v[:principle_id].to_i) ? v.merge(resolution_note: rule[:resolution]) : v
        end
      end

      violations
    end
  end
end
