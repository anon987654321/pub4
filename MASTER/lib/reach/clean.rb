# frozen_string_literal: true

require "open3"
require "timeout"

module Master
  module Reach
    # Clean — removes trailing whitespace, CRLF, and excess blank lines
    # from text files under a given path, using OPENBSD/clean.sh.
    class Clean
      # Was "../../../sh/clean.sh" -- resolved to a nonexistent repo-root
      # sh/clean.sh (missing the OPENBSD/ segment), a pre-existing bug
      # surfaced while flattening OPENBSD/sh/ into OPENBSD/ directly.
      SCRIPT = File.expand_path("../../../OPENBSD/clean.sh", __dir__).freeze
      NAME = "clean".freeze
      TIER = :dangerous
      TIMEOUT_S = 120 # clean.sh must not wedge the pipeline (ROBUSTNESS)

      def initialize(root:, governor:, event_bus: nil)
        @bus = event_bus
        @root = root
        @governor = governor
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}",
                          category: :validation) unless File.exist?(target) || Dir.exist?(target)

        guard = @governor.permit?(NAME, TIER, "clean #{target}")
        return guard if guard.err?

        out, err, status = run_bounded("zsh", SCRIPT, target)
        return Result.err("clean timed out after #{TIMEOUT_S}s", category: :timeout) if status.nil?
        return Result.err("clean failed: #{err.strip}", category: :unknown) unless status.success?

        cleaned = out.lines.grep(/^Cleaned:/).map { |l| l.sub("Cleaned: ", "").chomp }
        @bus&.publish("tool:clean", path: target, count: cleaned.size)
        Result.ok("cleaned #{cleaned.size} file(s):\n#{cleaned.join("\n")}")
      rescue StandardError => e
        Result.err("clean: #{e.message}", category: :unknown)
      end

      private

      # Shell-out with a hard time budget: read stdout/stderr on separate threads
      # (so a full pipe can't deadlock the wait) and kill a child that overruns,
      # rather than blocking the caller forever. Returns a nil status on timeout.
      def run_bounded(*cmd)
        # pgroup: true isolates the child (and any grandchildren clean.sh spawns)
        # in their own process group so a timeout can reap the whole tree, not
        # just zsh — otherwise orphaned children keep running past the kill.
        Open3.popen3(*cmd, pgroup: true) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }
          begin
            Timeout.timeout(TIMEOUT_S) { wait_thr.value }
            [out_reader.value, err_reader.value, wait_thr.value]
          rescue Timeout::Error
            terminate(wait_thr.pid)
            out_reader.kill
            err_reader.kill
            [nil, nil, nil]
          end
        end
      end

      def terminate(pid)
        pgid = Process.getpgid(pid)
        Process.kill("TERM", -pgid)
        sleep 0.2
        Process.kill("KILL", -pgid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end
  end
end
