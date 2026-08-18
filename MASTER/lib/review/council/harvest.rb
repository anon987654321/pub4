# frozen_string_literal: true

require "fileutils"

module Master
  module Review
    module Council
      # Council output used to die in the session log: four tree-wide
      # critiques ran on 2026-08-18 and the only complete deliberation
      # survived as scrollback in a scratchpad file. A verdict nobody can
      # find later was never given. Every Critique#run now lands here —
      # issues, proposals, challenges, picks — under .master/, which is
      # local runtime state and never committed.
      module Harvest
        DIR = "critiques"

        module_function

        def write(mode:, files:, feedback:, ideas:, cherry:, root: Master::ROOT)
          dir = File.join(root, ".master", DIR)
          FileUtils.mkdir_p(dir)
          slug = mode.to_s.gsub(/[^a-z0-9]+/i, "_").downcase
          path = File.join(dir, "#{slug}_#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.md")
          body = render(mode:, files:, feedback:, ideas:, cherry:)
          File.write(path, body)
          File.write(File.join(dir, "#{slug}_latest.md"), body)
          path
        end

        def render(mode:, files:, feedback:, ideas:, cherry:)
          lines = ["# council critique — #{mode}", "", "files: #{Array(files).join(', ')}", ""]
          lines << "## panel"
          Array(feedback).each do |entry|
            lines << "### #{entry[:persona]}"
            lines << entry[:feedback].to_s.strip
            lines << ""
          end
          lines << "## proposals and challenges"
          lines << (ideas.is_a?(Hash) ? format_ideas(ideas) : ideas.to_s)
          lines << ""
          lines << "## cherry-picked"
          Array(cherry).each { |pick| lines << "- #{pick}" }
          lines.join("\n") + "\n"
        end

        def format_ideas(ideas)
          parts = []
          proposals = Array(ideas[:ideas])
          parts << proposals.map { |idea| "- #{idea}" }.join("\n") if proposals.any?
          challenges = Array(ideas[:critiques])
          if challenges.any?
            parts << "\n### adversarial challenges\n"
            parts << challenges.join("\n\n")
          end
          final = ideas[:final].to_s
          parts << "\n### synthesis\n\n#{final}" unless final.empty?
          parts.join("\n")
        end
      end
    end
  end
end
