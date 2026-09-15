# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"

module Master
  module Voice
    # Manages the human-readable SOUL.md Evolution Protocol.
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

          # The proposal is a file under .master/, and anything can write it after
          # `propose` checked it. Approval is the write, so it checks again.
          drift = measure_drift(@soul, proposal)
          return blocked_proposal_message(drift) if drift[:absolute_changed].any?

          # SOUL.md carries no version line and no changelog table, so the
          # revision an approval makes is the commit, and the reply names it.
          updated = proposal
          persist(@soul_path, updated)
          File.unlink(@proposal_path)
          @soul = updated
          commit = commit_approval
          commit ? "soul updated in #{commit}" : "soul updated (git commit failed)"
        rescue StandardError => e
          "approve error: #{e.message}"
        end

        def reject
          return "no pending proposal" unless File.exist?(@proposal_path)

          File.unlink(@proposal_path)
          "proposal rejected"
        end
      end

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

      # What booted: soul.yml's revision and persona, the ones the boot line
      # names, then SOUL.md's opening sentence. SOUL.md itself carries no
      # Version or Persona line; its own fields stand in only without soul.yml.
      def summary
        law = File.exist?(law_path) ? Master.load_yaml(law_path).to_h : {}
        version = law["version"] || extract_version
        persona = law["persona"] || extract_field("Persona")
        opening = @soul.lines.find { |line| line.match?(/\A[^#\s]/) }.to_s[/\A.*?[.!?](?=\s|\z)/].to_s
        ["soul0: rev #{version}, persona #{persona.to_s.empty? ? 'none' : persona}", opening].reject(&:empty?).join("\n")
      end

      # The commits that touched SOUL.md, which is where an approval records
      # itself.
      def changelog
        log, status = Master::Io::Exec.capture2e("git", "-C", @root, "log", "-n", "10", "--date=short",
                                                 "--format=%h %ad %s", "--", "data/SOUL.md")
        status.success? && !log.strip.empty? ? log.strip : "no git history for data/SOUL.md"
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

      # The short hash of the approval commit, or nil when git refused it.
      def commit_approval
        relative = Pathname.new(@soul_path).relative_path_from(Pathname.new(@root)).to_s
        _, add_status = Master::Io::Exec.capture2e("git", "-C", @root, "add", "--", relative)
        return unless add_status.success?

        _, commit_status = Master::Io::Exec.capture2e(
          "git", "-C", @root, "commit", "-m", "soul: evolution protocol update",
          "-m", Master::Core::World::COMMIT_TRAILER
        )
        return unless commit_status.success?

        head, head_status = Master::Io::Exec.capture2e("git", "-C", @root, "rev-parse", "--short", "HEAD")
        head_status.success? ? head.strip : nil
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

      def law_path = File.join(@root, "data", "soul.yml")

      def load_soul
        File.exist?(@soul_path) ? File.read(@soul_path, encoding: "UTF-8") : ""
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "voice.soul.load", path: @soul_path)
        ""
      end

      def extract_version = @soul[/^Version: ([\d.]+)/, 1] || "1.0.0"
      def extract_field(name) = @soul[/^#{Regexp.escape(name)}:\s*(.+)/, 1].to_s.strip

      def measure_drift(old_doc, new_doc)
        {
          absolute_changed: removed_patterns(old_doc, new_doc, ABSOLUTE_PATTERNS),
          protected_changed: removed_patterns(old_doc, new_doc, PROTECTED_PATTERNS),
        }
      end

      def removed_patterns(old_doc, new_doc, patterns)
        patterns.select { |pattern| old_doc.match?(pattern) && !new_doc.match?(pattern) }.map(&:source)
      end
    end
  end
end
