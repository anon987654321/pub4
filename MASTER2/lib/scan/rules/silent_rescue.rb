# frozen_string_literal: true

module MASTER
  module Scan
    module Rules
      # SilentRescue -- flags rescue blocks that swallow exceptions without logging.
      # A rescue that returns only nil/next/{}/[] with no Logging.* call is a silent swallow.
      module SilentRescue
        include Scan::Rule

        # Matches rescue blocks whose bodies contain no Logging call and
        # only return a neutral value (nil, {}, [], next, empty string).
        SILENT_BODY = /rescue(?:\s+\w[\w:]*(?:\s*=>\s*\w+)?)?\s*\n\s*(?:nil|next|\{\}|\[\]|""|'')\s*\n/m

        def self.check(code, path: nil)
          findings = []
          # Line-by-line: flag any `rescue` line not followed by Logging within 3 lines
          lines = code.lines
          lines.each_with_index do |line, idx|
            next unless line.match?(/^\s*rescue\b/)

            window = lines[idx + 1, 3].join
            next if window.match?(/Logging\.|raise\b|warn\b|log\b/)
            next if window.match?(/\S/) && !window.match?(/\A\s*(?:nil|next|\{\}|\[\]|""|''|\})\s*\z/m)

            findings << {
              rule:      :silent_rescue,
              name:      :silent_rescue,
              message:   "rescue with no Logging call -- exception swallowed silently",
              line:      idx + 1,
              severity:  :minor,
              autofix:   false,
              principle: nil,
            }
          end
          findings
        end
      end
    end
  end
end
