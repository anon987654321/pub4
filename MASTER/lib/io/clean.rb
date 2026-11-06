# frozen_string_literal: true

require_relative "exec"

module Master
  module Io
    # Clean — removes trailing whitespace, CRLF, and excess blank lines
    # from text files under a given path, using OPENBSD/dev/clean.sh.
    class Clean
      SCRIPT = File.expand_path("../../../OPENBSD/dev/clean.sh", __dir__).freeze
      NAME = "clean".freeze
      TIER = :dangerous
      # clean.sh must not wedge the pipeline (ROBUSTNESS)
      TIMEOUT_S = 120

      def initialize(root:, governor:, event_bus: nil, timeout_s: TIMEOUT_S)
        @bus = event_bus
        @root = root
        @governor = governor
        @timeout_s = timeout_s
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}",
                          category: :validation) unless File.exist?(target) || Dir.exist?(target)

        guard = @governor.permit?(NAME, TIER, "clean #{target}")
        return guard if guard.err?

        out, err, status = run_bounded("zsh", SCRIPT, target)
        return Result.err("clean timed out after #{@timeout_s}s", category: :timeout) if status.nil?
        return Result.err("clean failed: #{err.strip}", category: :unknown) unless status.success?

        cleaned = out.lines.grep(/^Cleaned:/).map { |l| l.sub("Cleaned: ", "").chomp }
        @bus&.publish("tool:clean", path: target, count: cleaned.size)
        Result.ok("cleaned #{cleaned.size} file(s):\n#{cleaned.join("\n")}")
      rescue StandardError => e
        Result.err("clean: #{e.message}", category: :unknown)
      end

      private

      # Keep Clean's timeout result contract while delegating pipe draining and
      # process-group termination to the shared runner.
      def run_bounded(*cmd)
        Master::Io::Exec.capture3(*cmd, timeout: @timeout_s, raise_on_timeout: true)
      rescue Master::Io::Exec::TimeoutError
        [nil, nil, nil]
      end
    end
  end
end
