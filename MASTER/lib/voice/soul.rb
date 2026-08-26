# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"


module Master
  module Voice
    class Soul
      # The propose -> diff -> approve/reject workflow for SOUL.md changes —
      # separate from Soul's own read-only accessors and rollback.
      module ProposalLifecycle
        def propose(rationale, agent: @agent)
          return "no agent available for drafting" unless agent

          draft = agent.ask_once(proposal_prompt(rationale)).to_s.strip
          return "draft failed" if draft.empty?

          save_proposal(draft)
        rescue StandardError => e
          "proposal error: #{e.message}"
        end

        def diff
          return "no pending proposal" unless File.exist?(@proposal_path)

          changes = changed_lines(@soul.lines, proposal.lines)
          changes.empty? ? "(no visible changes)" : changes.join("\n")
        end

        def approve
          return "no pending proposal" unless File.exist?(@proposal_path)

          version = bump_version(extract_version, :patch)
          updated = with_version_and_changelog(proposal, version)
          persist(@soul_path, updated)
          File.unlink(@proposal_path)
          @soul = updated
          committed = commit_approval(version)
          "soul updated to v#{version}#{committed ? "" : " (git commit failed)"}"
        rescue StandardError => e
          "approve error: #{e.message}"
        end

        def reject
          return "no pending proposal" unless File.exist?(@proposal_path)

          File.unlink(@proposal_path)
          "proposal rejected"
        end

        def propose_from_violations(rule_id, sample_violations, agent: @agent)
          return "no agent available" unless agent

          examples = sample_violations.first(3).map { |violation| violation_example(violation) }.join("\n")
          rationale = "Recurring scan rule '#{rule_id}' flagged #{sample_violations.size} violations " \
                      "across multiple files and cycles:\n#{examples}\nPropose whether the codebase axioms or soul " \
                      "principles should acknowledge this pattern or whether the rule needs refinement."
          propose(rationale, agent:)
        end
      end
    end
  end
end

module Master
  module Voice
    # Manages the human-readable SOUL.md Evolution Protocol.
    class Soul
      include ProposalLifecycle

      SOUL_PATH = File.join(Master::ROOT, "data", "SOUL.md").freeze
      PROPOSAL_PATH = File.join(Master::ROOT, ".master", "soul_proposal.md").freeze
      ABSOLUTE_PATTERNS = [/anti-simulation rule/i, /golden rule/i, /preserve.*then.*improve/i].freeze
      PROTECTED_PATTERNS = [/voice character/i, /terse.*direct.*dark/i].freeze

      def initialize(root: Master::ROOT, agent: nil)
        @root = File.expand_path(root)
        @agent = agent
        @soul_path = File.join(@root, "data", "SOUL.md")
        @proposal_path = File.join(@root, ".master", "soul_proposal.md")
        @soul = load_soul
      end

      def wire_agent(agent) = @agent = agent

      def summary
        voice = extract_field("Voice").to_s.lines.first.to_s.strip[0, 120]
        "SOUL.md v#{extract_version} | persona: #{extract_field("Persona")}\n#{voice}"
      end

      def changelog
        block = @soul[/## Changelog\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
        block.empty? ? "(no changelog)" : block
      end

      def rollback
        previous = previous_revision
        return "no git history for data/SOUL.md" unless previous

        restored, status = Master::Io::Exec.capture2e("git", "-C", @root, "show", "#{previous}:data/SOUL.md")
        return "rollback error: #{restored.strip}" unless status.success?

        persist(@soul_path, restored)
        @soul = restored
        "rolled back to #{previous}"
      rescue StandardError => e
        "rollback error: #{e.message}"
      end

      def system_prompt
        voice = @soul[/## Voice\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
        values = @soul[/## Values\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
        "#{voice}\n\n#{values}"
      end

      private

      def save_proposal(draft)
        drift = measure_drift(@soul, draft)
        return blocked_proposal_message(drift) if drift[:absolute_changed].any?

        persist(@proposal_path, draft)
        "proposal saved#{protected_change_warning(drift)}. " \
          "Review with `soul diff`, approve with `soul approve`, reject with `soul reject`."
      end

      def changed_lines(old_lines, new_lines)
        removals = old_lines.reject { |line| new_lines.include?(line) }
        additions = new_lines.reject { |line| old_lines.include?(line) }
        removals.first(10).map { |line| "- #{line.chomp}" } +
          additions.first(10).map { |line| "+ #{line.chomp}" }
      end

      def proposal_prompt(rationale)
        <<~PROMPT
          You are editing SOUL.md — a constitutional identity document for an AI coding agent.
          Current document:
          #{@soul}

          Proposed change rationale: #{rationale}

          Draft ONLY the minimal changes needed. Preserve the anti-simulation rule,
          golden rule, and voice character unchanged.
          Output the full updated SOUL.md. No preamble.
        PROMPT
      end

      def blocked_proposal_message(drift)
        changed = drift[:absolute_changed].join(", ")
        "BLOCKED: proposal changes ABSOLUTE sections: #{changed}. Add /override to force."
      end

      def protected_change_warning(drift)
        changed = drift[:protected_changed]
        changed.any? ? " [PROTECTED sections affected: #{changed.join(", ")}]" : ""
      end

      def with_version_and_changelog(document, version)
        updated = document.sub(/Version: [\d.]+/, "Version: #{version}")
        date = Time.now.strftime("%Y-%m-%d")
        entry = "| #{version} | #{date} | Evolution Protocol change | Approved via `soul approve` |\n"
        updated.sub(/\| 1\.0\.0 \|/, entry + "| 1.0.0 |")
      end

      def commit_approval(version)
        relative = Pathname.new(@soul_path).relative_path_from(Pathname.new(@root)).to_s
        _, add_status = Master::Io::Exec.capture2e("git", "-C", @root, "add", "--", relative)
        return false unless add_status.success?

        _, commit_status = Master::Io::Exec.capture2e(
          "git", "-C", @root, "commit", "-m", "soul: v#{version} — evolution protocol update"
        )
        commit_status.success?
      end

      def previous_revision
        output, status = Master::Io::Exec.capture2e("git", "-C", @root, "log", "--format=%H", "--", "data/SOUL.md")
        status.success? ? output.lines[1]&.strip : nil
      end

      def persist(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        temporary = "#{path}.tmp.#{Process.pid}"
        File.write(temporary, content)
        File.rename(temporary, path)
      ensure
        File.unlink(temporary) if temporary && File.exist?(temporary)
      end

      def proposal = File.read(@proposal_path, encoding: "UTF-8")

      def load_soul
        File.exist?(@soul_path) ? File.read(@soul_path, encoding: "UTF-8") : ""
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "voice.soul.load", path: @soul_path)
        ""
      end

      def extract_version = @soul[/^Version: ([\d.]+)/, 1] || "1.0.0"
      def extract_field(name) = @soul[/^#{Regexp.escape(name)}:\s*(.+)/, 1].to_s.strip

      def bump_version(version, level)
        major, minor, patch = version.split(".").map(&:to_i)
        { major: "#{major + 1}.0.0", minor: "#{major}.#{minor + 1}.0", patch: "#{major}.#{minor}.#{patch + 1}" }
          .fetch(level)
      end

      def measure_drift(old_doc, new_doc)
        {
          absolute_changed: removed_patterns(old_doc, new_doc, ABSOLUTE_PATTERNS),
          protected_changed: removed_patterns(old_doc, new_doc, PROTECTED_PATTERNS),
        }
      end

      def removed_patterns(old_doc, new_doc, patterns)
        patterns.select { |pattern| old_doc.match?(pattern) && !new_doc.match?(pattern) }.map(&:source)
      end

      def violation_example(violation) = "  L#{violation[:line]}: #{violation[:message]}"
    end
  end
end
