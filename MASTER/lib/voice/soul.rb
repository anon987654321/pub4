# frozen_string_literal: true

module Master
  module Voice
    # Compatibility facade for the /soul command.
    #
    # Identity and constitutional meaning are owned by Master::Soul in
    # lib/soul.rb. This facade reads and reports that source; it does not
    # generate, approve, overwrite or roll back its own constitution.
    class Soul
      def initialize(root: Master::ROOT, agent: nil)
        @root = Master.master_root(root:)
        @repo_root = @root == Master::ROOT ? Master::REPO_ROOT : File.dirname(@root)
        @agent = agent
      end

      def summary
        Master::Soul.load!(root: @root)
        manifest = Master.soul_config(root: @root)
        [
          "soul0: rev #{manifest.fetch("version")}, persona #{manifest.fetch("persona", "none")}",
          Master::Soul::IDENTITY
        ].join("\n")
      end

      def changelog
        output, status = git_log
        status.success? && !output.strip.empty? ? output.strip : "no Git history for the canonical Soul source"
      rescue StandardError => e
        "soul0: history unavailable, #{e.class}: #{e.message}"
      end

      def diff
        paths = canonical_paths
        output, status = Master::Io::Exec.capture2e("git", "-C", @repo_root, "diff", "--", *paths)
        return "soul0: diff unavailable, #{output.strip}" unless status.success?

        output.strip.empty? ? "soul0: no uncommitted canonical Soul changes" : output
      rescue StandardError => e
        "soul0: diff unavailable, #{e.class}: #{e.message}"
      end

      def propose(_rationale, agent: @agent)
        "BLOCKED: Soul is Ruby-owned. Propose a reviewed change to MASTER/lib/soul.rb and update the soul.yml digest; proposals cannot rewrite their own authority."
      end

      def approve
        "BLOCKED: canonical Soul changes require an operator-authored Git commit and a matching soul.yml integrity digest."
      end

      def reject
        proposal = File.join(@root, ".master", "soul_proposal.md")
        return "no pending Soul proposal" unless File.file?(proposal)

        File.unlink(proposal)
        "legacy Markdown Soul proposal discarded"
      rescue StandardError => e
        "soul0: proposal cleanup failed, #{e.class}: #{e.message}"
      end

      def rollback
        "BLOCKED: use a reviewed Git revert of MASTER/lib/soul.rb and MASTER/data/soul.yml together."
      end

      def system_prompt
        Master::Soul.prompt(root: @root)
      end

      private

      def canonical_paths
        prefix = @repo_root == Master::REPO_ROOT ? "MASTER/" : ""
        %W[#{prefix}lib/soul.rb #{prefix}data/soul.yml]
      end

      def git_log
        Master::Io::Exec.capture2e(
          "git", "-C", @repo_root, "log", "-n", "10", "--date=short",
          "--format=%h %ad %s", "--", *canonical_paths
        )
      end
    end
  end
end
