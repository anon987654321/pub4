# frozen_string_literal: true

require "json"
require_relative "exec"

module Master
  module Io
    # GitHub delivery for verified worktree changes.
    #
    # Git remains the local transport; GitHub is the merge authority. MASTER
    # pushes the isolated branch, opens one PR, asks GitHub to merge it, and
    # waits for the PR to become MERGED. Missing gh/auth/check capability is
    # a delivery failure, never permission to bypass the PR boundary.
    class GitHubOperations
      Result = Data.define(:ok, :summary, :number, :url, :merged_sha)

      DEFAULT_TIMEOUT = Integer(ENV.fetch("MASTER_GITHUB_TIMEOUT", "120"))
      DEFAULT_MERGE_TIMEOUT = Integer(ENV.fetch("MASTER_GITHUB_MERGE_TIMEOUT", "1800"))
      POLL_SECONDS = Integer(ENV.fetch("MASTER_GITHUB_POLL_SECONDS", "5"))

      def initialize(root:, repo: nil, out: $stderr, executor: Exec)
        @root = File.expand_path(root)
        @out = out
        @executor = executor
        @repo = repo || origin_repo
      end

      def github_remote?
        !@repo.nil?
      end

      def available?
        _out, status = gh("--version", timeout: 10)
        return false unless status.success?

        _out, status = gh("auth", "status", timeout: 20)
        status.success?
      end

      def publish_and_merge!(branch:, base:, expected_head:, title:, body:, timeout: DEFAULT_MERGE_TIMEOUT)
        return Result.new(false, "GitHub delivery requires a github.com origin", nil, nil, nil) unless github_remote?
        return Result.new(false, "GitHub delivery unavailable — install gh and authenticate with gh auth login", nil, nil, nil) unless available?

        pr = create_pr(branch:, base:, title:, body:)
        return pr unless pr.ok

        number = pr.number
        current = view(number)
        if current[:head] != expected_head
          return Result.new(
            false,
            "GitHub PR ##{number} head changed from #{expected_head[0, 12]} to #{current[:head].to_s[0, 12]}",
            number...[truncated]