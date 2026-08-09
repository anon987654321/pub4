# frozen_string_literal: true

require "fileutils"
require "open3"
require "time"

module Master
  module Trace
    class SelfEvolutionTrigger
      MIN_REFACTOR_LINES = 40

      def initialize(root:)
        @root = root
      end

      def call
        return "self-evolution: disabled" if ENV["MASTER_SELF_EVOLUTION"] == "0"
        return "self-evolution: no significant refactor" unless significant_refactor?

        before = diff_stat
        scan = run_master("/scan MASTER/lib")
        fix = run_master("/fix MASTER/lib")
        after = diff_stat
        write_capture(before:, scan:, fix:, after:)
        "self-evolution: scan=#{scan[:status]} fix=#{fix[:status]}"
      rescue StandardError => e
        write_capture(before: diff_stat, scan: { status: :error, output: e.message }, fix: {}, after: diff_stat)
        "self-evolution: #{e.message}"
      end

      private

      attr_reader :root

      def significant_refactor?
        changed_master_lib_lines >= MIN_REFACTOR_LINES
      end

      def changed_master_lib_lines
        out, status = Master::Io::Exec.capture2e("git", "-C", root, "diff", "--numstat", "HEAD", "--", "MASTER/lib")
        return 0 unless status.success?

        out.lines.sum do |line|
          added, deleted, = line.split(/\s+/, 3)
          added.to_i + deleted.to_i
        end
      end

      def diff_stat
        out, status = Master::Io::Exec.capture2e("git", "-C", root, "diff", "--stat", "HEAD", "--", "MASTER/lib")
        status.success? ? out.strip : "diff unavailable"
      end

      def run_master(message)
        # MASTER_SCAN_AUTOFIX=0 for the same reason bin/gate sets it: this runs
        # `/scan MASTER/lib` and then `/fix MASTER/lib` and records what each did
        # separately. MASTER_AUTOFIX gates the background fix loop, not the
        # AstFixer pass inside /scan, so without this the scan step wrote to the
        # tree and the capture attributed its edits to /fix.
        env = {
          "MASTER_SAFE_MODE" => "1",
          "MASTER_BACKGROUND" => "0",
          "MASTER_AUTOFIX" => "0",
          "MASTER_SCAN_AUTOFIX" => "0",
          "MASTER_WATCH" => "0",
          "MASTER_HEARTBEAT" => "0",
          "MASTER_SELF_EVOLUTION" => "0",
        }
        out, status = Master::Io::Exec.capture2e(env, Master::BUNDLE_BIN, "exec", "ruby", "bin/cli", "--message", message, chdir: root)
        { status: status.success? ? :ok : :failed, output: out.to_s.lines.last(80).join }
      end

      def write_capture(before:, scan:, fix:, after:)
        path = File.join(root, "runtime", "self_evolution.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") do |file|
          file.puts "## #{Time.now.utc.iso8601}"
          file.puts "Before:"
          file.puts before.to_s.empty? ? "(no diff)" : before
          file.puts "Scan: #{scan[:status]}"
          file.puts scan[:output].to_s
          file.puts "Fix: #{fix[:status]}"
          file.puts fix[:output].to_s
          file.puts "After:"
          file.puts after.to_s.empty? ? "(no diff)" : after
          file.puts
        end
      end
    end
  end
end
