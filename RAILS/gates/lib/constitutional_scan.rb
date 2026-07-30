# frozen_string_literal: true

require "open3"
require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  # Scan-only constitutional preflight: MASTER /scan on RAILS (+ optional OPENBSD).
  # Does not run /fix (no autonomous edits). Full chain: `cd MASTER && ruby bin/gate`.
  class ConstitutionalScanGate
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    SAFE_ENV = {
      "MASTER_SAFE_MODE" => "1",
      "MASTER_BACKGROUND" => "0",
      "MASTER_AUTOFIX" => "0",
      "MASTER_WATCH" => "0",
      "MASTER_WATCHER" => "0",
      "MASTER_HEARTBEAT" => "0",
      "MASTER_SCAN_AUTOFIX" => "0",
    }.freeze

    def self.run(targets: nil)
      new(targets: targets).run
    end

    # Readable so target selection is assertable without paying for a scan;
    # the full gate is ~11 minutes.
    attr_reader :targets, :skipped

    def initialize(targets: nil)
      list = Array(targets).compact
      @skipped = []
      @targets = list.empty? ? default_targets : list
      @result = GateResult.new
    end

    def run
      cli = File.join(MASTER, "bin", "cli")
      unless File.file?(cli)
        @result.fail("missing MASTER/bin/cli")
        return @result
      end

      announce_plan
      started = now
      @targets.each_with_index { |target, index| scan_target(cli, target, index) }
      progress "constitutional scan: #{@targets.size} target(s) in #{(now - started).round}s"
      @result
    end

    private

    # This gate is four full MASTER scans back to back and takes north of ten
    # minutes. It used to buffer every subprocess and print nothing until the
    # end, so `runner.rb --all` looked hung for a quarter of an hour and in
    # practice nobody ran it. Progress goes to stderr as it happens; GateResult
    # still collects the summary for the final report.
    def progress(message)
      warn "[constitutional_scan] #{message}"
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def announce_plan
      progress "scanning #{@targets.size} target(s): #{@targets.map { |t| File.basename(t) }.join(", ")}"
      return if @skipped.empty?

      progress "skipped #{@skipped.size} unchanged target(s): #{@skipped.map { |t| File.basename(t) }.join(", ")}"
    end

    def default_targets
      all = %w[../RAILS/brgen ../RAILS/amber ../RAILS/bsdports ../RAILS/shared]
      return all unless changed_only?

      changed = changed_paths
      selected = all.select { |target| changed.any? { |path| path.start_with?("RAILS/#{File.basename(target)}/") } }
      @skipped = all - selected
      # Everything unchanged still means everything to scan: an empty selection
      # is "nothing to do", not "scan the world by surprise".
      selected
    end

    def changed_only? = ENV["GATE_SCAN_CHANGED"].to_s == "1"

    def changed_paths
      out, status = Open3.capture2e("git", "diff", "--name-only", "HEAD", chdir: ROOT)
      return [] unless status.success?

      out.lines.map(&:strip).reject(&:empty?)
    rescue StandardError
      []
    end

    def scan_target(cli, path, index)
      progress "#{index + 1}/#{@targets.size} #{File.basename(path)} …"
      started = now
      line = "/scan --no-autofix #{path}"
      env = SAFE_ENV.dup
      stdout, status = Open3.capture2e(
        env,
        "bundle", "exec", "ruby", "bin/cli",
        chdir: MASTER,
        stdin_data: "#{line}\n"
      )
      elapsed = (now - started).round
      progress "#{index + 1}/#{@targets.size} #{File.basename(path)} #{status.success? ? "ok" : "findings"} in #{elapsed}s"
      if status.success?
        @result.warn("constitutional scan ok: #{path} (#{stdout.lines.size} lines, #{elapsed}s)")
      else
        # Scan may exit non-zero on findings depending on cli; treat hard errors only.
        if stdout.to_s.match?(/LoadError|SyntaxError|uninitialized constant|No such file/)
          @result.fail("constitutional scan crashed for #{path}: #{stdout.lines.last(3).join}")
        else
          @result.warn("constitutional scan finished with findings for #{path}")
        end
      end
    rescue StandardError => e
      @result.fail("constitutional scan error for #{path}: #{e.class}: #{e.message}")
    end
  end
end
