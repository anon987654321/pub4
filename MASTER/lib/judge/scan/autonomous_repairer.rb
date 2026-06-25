# frozen_string_literal: true

module Master
  module Judge
    module Scan
      class AutonomousRepairer
        def self.heal(path:, source:, event_bus: nil)
          fix = AstFixer.fix(path, source, event_bus: event_bus)
          healed = fix.changed ? File.read(path, encoding: "UTF-8") : source
          Result.ok(healed)
        rescue StandardError => e
          Result.err("autonomous repair failed: #{e.message}", category: :syntax_collapse)
        end
      end
    end
  end
end