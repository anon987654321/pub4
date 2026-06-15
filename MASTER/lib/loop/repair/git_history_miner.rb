# frozen_string_literal: true

require "open3"

module Master
  module Loop
    module Repair
      class GitHistoryMiner
        DEFAULT_PATTERNS = [
          /fix/i,
          /refactor/i,
          /rollback/i,
          /repair/i,
          /runtime/i,
          /telemetry/i,
          /namespace/i,
        ].freeze

        def initialize(root: Dir.pwd)
          @root = root
        end

        def recent(limit: 100)
          out, = Open3.capture2e(
            "git",
            "log",
            "--oneline",
            "-n",
            limit.to_s,
            chdir: @root
          )

          out.lines.map(&:strip)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "git_history_miner.recent_commits")
          []
        end

        def valuable(limit: 100, patterns: DEFAULT_PATTERNS)
          recent(limit: limit).select do |line|
            patterns.any? { |pattern| pattern.match?(line) }
          end
        end
      end
    end
  end
end
