# frozen_string_literal: true

require "open3"

module Master
  module Reach
    # CE01: PR review, issue triage, status check via gh CLI.
    class Github
      NAME = "github".freeze

      def initialize(root: Dir.pwd, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def pr_status(number:)
        run_gh("pr", "view", number.to_s, "--json", "state,title,reviewDecision")
      end

      def issue_triage(state: "open", limit: 10)
        run_gh("issue", "list", "--state", state, "--limit", limit.to_s)
      end

      def repo_status
        run_gh("repo", "view", "--json", "name,url,defaultBranchRef")
      end

      private

      def run_gh(*args)
        out, status = Open3.capture2e("gh", *args, chdir: @root)
        @bus&.publish("reach:github", command: args.join(" "), ok: status.success?)
        status.success? ? Result.ok(out) : Result.err(out.strip)
      rescue Errno::ENOENT
        Result.err("gh CLI not found in PATH")
      end
    end
  end
end