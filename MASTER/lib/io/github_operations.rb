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
            number,
            pr.url,
            nil,
          )
        end

        merge_output, merge_status = gh(
          "pr", "merge", number.to_s, "--squash", "--delete-branch",
          timeout: [DEFAULT_TIMEOUT, 300].max
        )

        unless merge_status.success?
          merge_output, merge_status = gh(
            "pr", "merge", number.to_s, "--squash", "--delete-branch", "--auto",
            timeout: [DEFAULT_TIMEOUT, 300].max
          )
        end

        unless merge_status.success?
          return Result.new(
            false,
            "GitHub PR ##{number} merge request failed: #{compact(merge_output)}",
            number,
            pr.url,
            nil,
          )
        end

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_i
        loop do
          state = view(number)
          if state[:state] == "MERGED"
            return Result.new(true, "GitHub PR ##{number} merged as #{state[:merge_sha].to_s[0, 12]}", number, pr.url, state[:merge_sha])
          end
          return Result.new(false, "GitHub PR ##{number} closed before merge", number, pr.url, nil) if state[:state] == "CLOSED"
          if state[:head] && state[:head] != expected_head
            return Result.new(false, "GitHub PR ##{number} head changed while merging", number, pr.url, nil)
          end

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0

          sleep([POLL_SECONDS, remaining].min)
        end

        Result.new(false, "GitHub PR ##{number} did not become MERGED before the delivery deadline", number, pr.url, nil)
      rescue StandardError => e
        Result.new(false, "GitHub delivery failed: #{e.class}: #{e.message}", nil, nil, nil)
      end

      private

      def origin_repo
        output, status = @executor.capture2e("git", "-C", @root, "remote", "get-url", "origin", timeout: DEFAULT_TIMEOUT)
        return nil unless status.success?

        normalize_repo(output)
      end

      def normalize_repo(remote)
        value = remote.to_s.strip
        value = value.sub(%r{\A(?:https?://|git://)github\.com/}, "")
        value = value.sub(%r{\A(?:ssh://)?git@github\.com[:/]}, "")
        value = value.sub(%r{\.git\z}, "")
        return nil unless value.match?(%r{\A[\w.-]+/[\w.-]+\z})
        value
      end

      def create_pr(branch:, base:, title:, body:)
        output, status = gh(
          "pr", "create",
          "--repo", @repo,
          "--head", branch,
          "--base", base,
          "--title", title,
          "--body", body,
          "--json", "number,url",
          timeout: [DEFAULT_TIMEOUT, 300].max
        )
        return Result.new(false, "GitHub PR create failed: #{compact(output)}", nil, nil, nil) unless status.success?

        data = JSON.parse(output)
        number = Integer(data.fetch("number"))
        Result.new(true, "GitHub PR ##{number} created", number, data.fetch("url").to_s, nil)
      rescue JSON::ParserError, KeyError, ArgumentError => e
        Result.new(false, "GitHub PR create returned invalid metadata: #{e.message}", nil, nil, nil)
      end

      def view(number)
        output, status = gh(
          "pr", "view", number.to_s,
          "--repo", @repo,
          "--json", "state,headRefOid,mergeCommit,mergedAt",
          "--jq",
          "[.state,.headRefOid,.mergeCommit.oid // \"\",.mergedAt // \"\"] | @tsv",
          timeout: 30
        )
        raise "gh pr view failed: #{compact(output)}" unless status.success?

        state, head, merge_sha, merged_at = output.to_s.strip.split("\t", 4)
        {
          state: state.to_s,
          head: head.to_s.empty? ? nil : head,
          merge_sha: merge_sha.to_s.empty? ? nil : merge_sha,
          merged_at: merged_at.to_s.empty? ? nil : merged_at,
        }
      end

      def gh(*args, timeout:)
        Master::Trace::Dmesg.status("github0", args.join(" "), io: @out)
        @executor.capture2e("gh", *args, chdir: @root, timeout:)
      end

      def compact(output)
        output.to_s.scrub.lines.map(&:strip).reject(&:empty?).last(3).join(" ")[0, 300]
      end
    end
  end
end
