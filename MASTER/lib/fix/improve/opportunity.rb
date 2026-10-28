# frozen_string_literal: true

module Master
  module Fix
    module Improve
      # One elevation opportunity: a file measured against its domain's ideal,
      # with the gap and the smallest step that narrows it. Opportunities carry
      # their evidence (signal names, measurements) so a reviewer can check the
      # claim without re-running anything.
      Opportunity = Struct.new(:domain, :path, :signal, :detail, :leverage, :fix,
                               keyword_init: true) do
        def finding(root:, line: 1)
          relative = path.delete_prefix("#{root}/").delete_prefix("#{root}\\")
          {
            law: LAW_ID,
            kind: :improvement,
            file: relative,
            line:,
            severity: SEVERITY,
            confidence: CONFIDENCE,
            message: "elevation[#{domain}] #{signal}: #{detail}",
            fix:,
          }
        end
      end
    end
  end
end
