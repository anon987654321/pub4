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
      # The deterministic tier, which is the one this gate wants and had never
      # asked for. The runtime hands /scan an agent, so every file was costing a
      # model round trip: measured 2026-09-06, brgen alone took 48 minutes of
      # wall clock against 35 seconds of CPU — idle in a TLS read, the same stall
      # MASTER_SCAN_DETERMINISTIC was added to MASTER for. A per-app finding
      # ceiling needs no model, and a gate nobody can afford to run is a gate
      # nobody runs.
      "MASTER_SCAN_DETERMINISTIC" => "1",
    }.freeze

    # And a bound, because the wait above had none. capture2e waits forever, so
    # a stalled provider or a hung boot stops the whole gate run with no output
    # and no verdict. Past this, the scan is a gate result rather than a wait.
    SCAN_TIMEOUT_S = Integer(ENV.fetch("GATE_SCAN_TIMEOUT_S", 900))

    def self.run(targets: nil)
      new(targets: targets).run
    end

    # Readable so target selection is assertable without paying for a scan;
    # the full gate is ~11 minutes.
    attr_reader :targets, :skipped

    BUDGET_PATH = File.expand_path("../../data/constitutional_budget.yml", __dir__)
    # `scan: done [profile: full] 410 violations | top DEAD_CODE=99 …`
    VIOLATION_LINE = /^scan: done\b[^\n]*?\b(\d+) violations/
    # And the other spelling of the same number: `scan: done [profile: aesthetic]
    # clean -- no violations`. A count regex that only knows the digits skipped
    # the clean line and matched the NEXT `scan: done`, which is the deep pass —
    # so a target whose aesthetic pass is clean was judged on a different
    # profile's number than a target whose aesthetic pass found something.
    # STUDIO read 317 and OPENBSD 72 against ceilings measured at 0 in the same
    # run that printed "clean".
    CLEAN_LINE = /^scan: done\b[^\n]*\bclean\b/

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
      @targets.each_with_index { |target, index| scan_target(target, index) }
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

    # All four trees, not the Rails half. MASTER judges every effect against its
    # constitution and the other three trees are effects; scanning only RAILS
    # left a law that never opens STUDIO's 155 source files or OPENBSD's 107 to
    # govern them anyway. Each target carries its own ceiling in
    # constitutional_budget.yml, so a tree can be over without hiding another.
    #
    # MASTER is here too, and it is not a duplicate of `rake selfcheck`: that
    # runs error and critical severities over lib and law, while this is the
    # whole registry over the whole tree, against a recorded number.
    DEFAULT_TARGETS = %w[
      ../RAILS/brgen ../RAILS/amber ../RAILS/bsdports ../RAILS/shared
      ../STUDIO ../OPENBSD ../MASTER
    ].freeze

    # RAILS/brgen for an app, STUDIO for a tree — the prefix a changed path must
    # carry to select its target.
    def repo_prefix(target)
      relative = target.sub(%r{\A\.\./}, "")
      "#{relative}/"
    end

    def default_targets
      all = DEFAULT_TARGETS
      return all unless changed_only?

      changed = changed_paths
      selected = all.select { |target| changed.any? { |path| path.start_with?(repo_prefix(target)) } }
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

    def scan_target(path, index)
      progress "#{index + 1}/#{@targets.size} #{File.basename(path)} …"
      started = now
      line = "/scan --no-autofix #{path}"
      stdout, status = bounded_scan(line)
      elapsed = (now - started).round
      if status == :timeout
        @result.fail("constitutional scan for #{path} passed #{SCAN_TIMEOUT_S}s and was killed — " \
                     "raise GATE_SCAN_TIMEOUT_S if the tree really is that big, or find what it is waiting on")
        return
      end

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
      count = first_pass_count(stdout)
      if count.nil?
        if stdout.to_s.match?(/LoadError|SyntaxError|uninitialized constant|No such file/)
          @result.fail("constitutional scan crashed for #{path}: #{stdout.lines.last(3).join}")
        else
          @result.inconclusive!("#{name}: scan printed no violation count (#{elapsed}s) — output shape changed?")
        end
        return
      end

      @result.checked!
      judge_count(name, count)
    rescue StandardError => e
      @result.fail("constitutional scan error for #{path}: #{e.class}: #{e.message}")
    end

    # The FIRST `scan: done` line and nothing else — the aesthetic pass, which is
    # what every ceiling in constitutional_budget.yml was measured against. Both
    # of its spellings count: a number, or "clean -- no violations", which is
    # zero and was being read as "no count here, try the next line".
    def first_pass_count(stdout)
      line = stdout.to_s.lines.find { |l| l.start_with?("scan: done") }
      return nil unless line
      return 0 if line.match?(CLEAN_LINE)

      digits = line[VIOLATION_LINE, 1]
      digits && Integer(digits)
    end

    # One scan, with a bound. Returns the output and either the exit status or
    # :timeout — the child is killed, so a stalled scan costs SCAN_TIMEOUT_S
    # rather than the rest of the day.
    def bounded_scan(line)
      Open3.popen2e(SAFE_ENV, "bundle", "exec", "ruby", "bin/cli", chdir: MASTER) do |stdin, out, wait|
        stdin.write("#{line}\n")
        stdin.close
        output = +""
        # Read on a thread: the pipe fills at 64KB and a scan prints more than
        # that, so waiting on the process first deadlocks against its own output.
        reader = Thread.new { output << out.read.to_s }
        finished = wait.join(SCAN_TIMEOUT_S)
        unless finished
          kill_tree(wait.pid)
          reader.join(5)
          next [output, :timeout]
        end

        reader.join
        [output, wait.value]
      end
    end

    # The CLI runs the scan in the same process, but a boot that shells out
    # leaves the child holding the pipe — TERM first, then KILL, so a process
    # ignoring the polite one still goes.
    def kill_tree(pid)
      Process.kill("TERM", pid)
      sleep 2
      Process.kill("KILL", pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
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
