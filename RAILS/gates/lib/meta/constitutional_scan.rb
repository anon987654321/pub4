# frozen_string_literal: true

require "open3"
require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Scan-only constitutional preflight: MASTER /scan on RAILS (+ optional OPENBSD).
  # Does not run /fix (no autonomous edits). Full chain: `cd MASTER && ruby bin/gate`.
  class ConstitutionalScanGate
    ROOT = File.expand_path("../../../..", __dir__)
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

    BUDGET_PATH = File.expand_path("../../data/constitutional_budget.yml", __dir__)
    # `scan: done [profile: full] 410 violations | top DEAD_CODE=99 …`
    VIOLATION_LINE = /^scan: done\b[^\n]*?\b(\d+) violations/

    def initialize(targets: nil)
      list = Array(targets).compact
      @skipped = []
      @targets = list.empty? ? default_targets : list
      @result = GateResult.new
      @measured = {}
    end

    # target basename => ceiling. Readable so the budget is assertable without
    # paying for a 21-minute scan.
    def budget
      @budget ||= (YAML.safe_load_file(BUDGET_PATH)&.dig("targets") || {})
    rescue StandardError => e
      warn "constitutional_scan: budget unreadable (#{e.class}) — running unbudgeted"
      {}
    end

    attr_reader :measured

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
      maybe_ratchet
      @result
    end

    # Compares a target's finding count against its recorded ceiling. Chasing zero
    # is explicitly not the goal here (TODO.md, Constitution Scan Debt) — what the
    # ceiling buys is that adding findings fails and lowering the number is a
    # deliberate commit, which is what routing everything to warn could not do.
    def judge_count(name, count)
      @measured[name] = count
      ceiling = budget[name]

      if ceiling.nil?
        @result.warn("constitutional scan: #{name} has no ceiling in #{File.basename(BUDGET_PATH)} (#{count} findings)")
        return
      end

      if count > ceiling
        @result.fail("constitutional scan: #{name} #{count} findings exceeds ceiling #{ceiling} " \
                     "(+#{count - ceiling}) — fix them or record a new ceiling with a reason")
      elsif count < ceiling
        @result.warn("constitutional scan: #{name} #{count} findings, under its #{ceiling} ceiling " \
                     "(-#{ceiling - count}) — GATE_SCAN_RATCHET=1 records the new low")
      else
        @result.warn("constitutional scan: #{name} at its #{ceiling} ceiling")
      end
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
    rescue StandardError => e
      warn "constitutional_scan: scan output unreadable (#{e.class})"
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
      name = File.basename(path)
      progress "#{index + 1}/#{@targets.size} #{name} #{status.success? ? "ok" : "findings"} in #{elapsed}s"

      # A crash is not a finding count, and `/scan` exits 0 whether it found 0 or
      # 410 — so the exit status says almost nothing and the count has to come out
      # of the output.
      #
      # Order matters: the marker grep used to run first and swept the whole
      # output, so a *finding* that quoted "uninitialized constant" or "No such
      # file" made a completed scan report as a crash. amber failed this gate on
      # 2026-08-03 having scanned cleanly to 79-plus findings. A run that printed
      # its violation count did not crash, whatever its findings say.
      count = stdout.to_s[VIOLATION_LINE, 1]
      if count.nil?
        if stdout.to_s.match?(/LoadError|SyntaxError|uninitialized constant|No such file/)
          @result.fail("constitutional scan crashed for #{path}: #{stdout.lines.last(3).join}")
        else
          @result.inconclusive!("#{name}: scan printed no violation count (#{elapsed}s) — output shape changed?")
        end
        return
      end

      @result.checked!
      judge_count(name, Integer(count))
    rescue StandardError => e
      @result.fail("constitutional scan error for #{path}: #{e.class}: #{e.message}")
    end

    # Same contract as MASTER's rake lint:spine: the number only moves down, and
    # only when someone asks for it.
    def maybe_ratchet
      return unless ENV["GATE_SCAN_RATCHET"].to_s == "1"

      lowered = @measured.select { |name, count| budget[name] && count < budget[name] }
      return progress("ratchet: nothing to lower") if lowered.empty?

      # Per-line, not one block. The old pattern was
      # /^targets:\n(?:  \w+: \d+\n)+/, which requires the entries to sit
      # directly under `targets:` — and every one of them is preceded by the
      # comment explaining why it moved. So the sub matched nothing, the file was
      # rewritten unchanged, and the progress line below still announced the new
      # numbers. On 2026-08-03 it reported "brgen → 329, amber → 164" and left
      # 411/207 on disk. Rewriting a line at a time also keeps the comments.
      body = File.read(BUDGET_PATH)
      lowered.each do |name, count|
        body = body.sub(/^(  #{Regexp.escape(name)}:)[ \t]+\d+$/, "\\1 #{count}")
      end
      File.write(BUDGET_PATH, body)

      # Never announce a write without confirming it landed — that is the exact
      # failure this comment describes.
      reread = (YAML.safe_load_file(BUDGET_PATH)&.dig("targets") || {})
      missed = lowered.reject { |name, count| reread[name] == count }
      unless missed.empty?
        @result.fail("constitutional scan: ratchet failed to record #{missed.keys.join(', ')} in " \
                     "#{File.basename(BUDGET_PATH)} — the file's shape no longer matches the rewrite")
        return
      end

      progress "ratchet: #{lowered.map { |name, count| "#{name} → #{count}" }.join(", ")}"
    end
  end
end
