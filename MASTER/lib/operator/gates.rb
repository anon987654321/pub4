# frozen_string_literal: true

# MASTER deploy gates in one explicit adapter. The RAILS gate registry loads
# this file, while the classes intentionally remain Deploy::* foreign-namespace
# adapters outside Zeitwerk.

require "open3"
require "json"
require "yaml"
require_relative "ruby_runner"
require_relative "../trace/dmesg"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../../RAILS/gates/support/bounded_command"
require_relative "../../../RAILS/tools/design_tokens"

# frozen_string_literal: true

module Deploy
  # Scan-only constitutional preflight: MASTER /scan on RAILS (+ optional OPENBSD).
  # Does not run /fix (no autonomous edits). Full chain: `cd MASTER && ruby bin/gate`.
  class ConstitutionalScanGate
    # The repository root: this file is MASTER/lib/operator/gates.rb.
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    RUBY = Operator::RubyRunner.ruby_cmd
    BUNDLE = Operator::RubyRunner.bundle_cmd
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
      new(targets:).run
    end

    # Readable so target selection is assertable without paying for a scan;
    # the full gate is ~11 minutes.
    attr_reader :targets, :skipped

    # The budget sits with the gates whose scan it bounds. This gate runs MASTER's
    # chain over RAILS, so the per-target seconds are RAILS' to declare, and a
    # copy here would be a second source that drifts.
    BUDGET_PATH = File.expand_path("../../RAILS/gates/data/constitutional_budget.yml", __dir__)
    # `scan: done [profile: full] 410 violations | top DEAD_CODE=99 …`
    VIOLATION_LINE = /^scan\d*: done\b[^\n]*?\b(\d+) violations/
    # And the other spelling of the same number: `scan: done [profile: aesthetic]
    # clean -- no violations`. A count regex that only knows the digits skipped
    # the clean line and matched the NEXT `scan: done`, which is the deep pass —
    # so a target whose aesthetic pass is clean was judged on a different
    # profile's number than a target whose aesthetic pass found something.
    # MASTER/tools read 317 and OPENBSD 72 against ceilings measured at 0 in the same
    # run that printed "clean".
    CLEAN_LINE = /^scan\d*: done\b[^\n]*\bclean\b/

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
      @result.inconclusive!("constitutional_scan: budget unreadable (#{e.class}: #{e.message}) — budget was not measured")
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
      Master::Trace::Dmesg.status("scan0", message)
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def announce_plan
      progress "scanning #{@targets.size} target(s): #{@targets.map { |t| File.basename(t) }.join(", ")}"
      return if @skipped.empty?

      progress "skipped #{@skipped.size} unchanged target(s): #{@skipped.map { |t| File.basename(t) }.join(", ")}"
    end

    # All four trees, not the Rails half. MASTER judges every effect against its
    # constitution and the other three trees are effects; scanning only RAILS
    # left a law that never opens MASTER/tools' 155 source files or OPENBSD's 107 to
    # govern them anyway. Each target carries its own ceiling in
    # constitutional_budget.yml, so a tree can be over without hiding another.
    #
    # MASTER is here too, and it is not a duplicate of `rake selfcheck`: that
    # runs error and critical severities over lib and law, while this is the
    # whole registry over the whole tree, against a recorded number.
    DEFAULT_TARGETS = %w[
      ../RAILS/brgen ../RAILS/amber ../RAILS/bsdports ../RAILS/shared
      ../OPENBSD ../MASTER
    ].freeze

    # RAILS/brgen for an app, MASTER/tools for a tree — the prefix a changed path must
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
      out, status = BoundedCommand.capture2e("git", "diff", "--name-only", "HEAD", chdir: ROOT)
      unless BoundedCommand.success?(status)
        @result.inconclusive!("constitutional_scan: git diff output unavailable — changed-file scope was not measured")
        return []
      end

      out.lines.map(&:strip).reject(&:empty?)
    rescue StandardError => e
      @result.inconclusive!("constitutional_scan: scan output unreadable (#{e.class}: #{e.message})")
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

      count = first_pass_count(stdout)
      return report_missing_count(path, name, stdout, elapsed) if count.nil?

      @result.checked!
      judge_count(name, count)
    rescue StandardError => e
      @result.fail("constitutional scan error for #{path}: #{e.class}: #{e.message}")
    end

    # A crash is not a finding count, and `/scan` exits 0 whether it found 0 or
    # 410 — so the exit status says almost nothing and the count has to come out
    # of the output.
    #
    # Order matters: the marker grep used to run first and swept the whole
    # output, so a *finding* that quoted "uninitialized constant" or "No such
    # file" made a completed scan report as a crash. amber failed this gate on
    # 2026-08-03 having scanned cleanly to 79-plus findings. A run that printed
    # its violation count did not crash, whatever its findings say.
    def report_missing_count(path, name, stdout, elapsed)
      if stdout.to_s.match?(/LoadError|SyntaxError|uninitialized constant|No such file/)
        @result.fail("constitutional scan crashed for #{path}: #{stdout.lines.last(3).join}")
      else
        @result.inconclusive!("#{name}: scan printed no violation count (#{elapsed}s) — output shape changed?")
      end
    end

    # The FIRST `scan: done` line and nothing else — the aesthetic pass, which is
    # what every ceiling in constitutional_budget.yml was measured against. Both
    # of its spellings count: a number, or "clean -- no violations", which is
    # zero and was being read as "no count here, try the next line".
    def first_pass_count(stdout)
      # /scan speaks as a dmesg unit, "scan0: done, …"; "scan: done" is the
      # spelling the recorded outputs in the tests still carry.
      line = stdout.to_s.lines.find { |l| l.match?(/\Ascan\d*: done\b/) }
      return unless line
      return 0 if line.match?(CLEAN_LINE)

      digits = line[VIOLATION_LINE, 1]
      digits && Integer(digits)
    end

    # One scan, with a bound. Returns the output and either the exit status or
    # :timeout — the child is killed, so a stalled scan costs SCAN_TIMEOUT_S
    # rather than the rest of the day.
    def bounded_scan(line)
      Open3.popen2e(SAFE_ENV, RUBY, BUNDLE, "exec", RUBY, "bin/cli", chdir: MASTER) do |stdin, out, wait|
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

# frozen_string_literal: true

module Deploy
  class MasterTtsGate
    # The repository root: this file is MASTER/lib/operator/gates.rb.
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")

    CHECKS = {
      "MASTER/lib/voice/speech.rb" => [
        "def edge_tts_available?",
        "def espeak_path",
        "synthesize_espeak(text_str) if espeak_path",
      ],
      "MASTER/lib/voice/tts_supervisor.rb" => [
        "BUNDLE_ISOLATION_KEYS",
        "BUNDLE_ISOLATION_KEYS.each { |key| env[key] = nil }",
      ],
      "MASTER/bin/tts-worker" => [
        "tts-worker --daemon",
        "EventMachine SSL support unavailable",
        "BUNDLE_ISOLATION_KEYS.each { |key| ENV.delete(key) }",
      ],
      "MASTER/bin/smoke" => [
        "tts-e2e poll",
        "tts-e2e",
      ],
      "OPENBSD/OPERATOR.sh" => [
        "espeak",
      ],
      "OPENBSD/etc/rc.d/master" => [
        "Master::Voice::TtsSupervisor.ensure_daemon!",
        "MASTER_TTS_TIMEOUT=45",
      ],
    }.freeze

    def self.run
      result = GateResult.new
      check_needles(result)
      check_tts_worker(result)
      check_host_backend(result)
      result
    end

    def self.check_needles(result)
      CHECKS.each do |relative_path, needles|
        result.checked!(needles.size)
        path = File.join(ROOT, relative_path)
        unless File.file?(path)
          result.fail("missing #{relative_path}")
          next
        end

        body = File.read(path)
        needles.each do |needle|
          result.fail("#{relative_path} missing #{needle.inspect}") unless body.include?(needle)
        end
      end
    end
    private_class_method :check_needles

    def self.check_tts_worker(result)
      result.checked!
      worker = File.join(MASTER, "bin", "tts-worker")
      result.fail("MASTER/bin/tts-worker must be executable") unless File.executable?(worker)
    end
    private_class_method :check_tts_worker

    def self.check_host_backend(result)
      return unless ENV["MASTER_TTS_REQUIRE_HOST_BACKEND"] == "1"

      host_backend = system("command", "-v", "edge-tts", out: File::NULL, err: File::NULL) ||
        system("command", "-v", "espeak", out: File::NULL, err: File::NULL) ||
        File.executable?("/usr/local/bin/espeak") ||
        File.executable?("/usr/bin/espeak")
      result.fail("host missing edge-tts/espeak backend") unless host_backend
    end
    private_class_method :check_host_backend
  end
end

# frozen_string_literal: true

module Deploy
  class MasterWebAssetsGate
    # The repository root: this file is MASTER/lib/operator/gates.rb.
    ROOT = File.expand_path("../../..", __dir__)
    FACE_CSS = File.join(ROOT, "MASTER", "web", "public", "face.css")
    WEB_ROOT = File.join(ROOT, "MASTER", "web")
    ASSETS_DIR = File.join(WEB_ROOT, "public", "assets")
    MANIFEST = File.join(ASSETS_DIR, ".manifest.json")
    REQUIRED = %w[face.css face.js face.runtime.js chat.js three.face.module.js].freeze
    # Same two files Operator::CiGuard uses to recognise vm23. Only there is a missing
    # precompiled manifest a deploy fault rather than an unbuilt checkout.
    DEPLOY_HOST_MARKERS = ["/etc/relayd.conf", "/var/db/pub4_vps"].freeze
    DEPLOY_SCRIPTS = {
      "OPENBSD/OPERATOR.sh" => :start_or_restart,
      # vps_on_vm_install.sh is not listed: it only execs vps_install_all.sh.
      "OPENBSD/bin/vps_install_all.sh" => :start_or_restart,
      "OPENBSD/bin/vps_console.exp" => :restart,
      "OPENBSD/bin/vps_deploy_master.sh" => :restart,
    }.freeze

    def self.run
      result = GateResult.new
      check_design_token_drift(result)
      check_manifest(result)
      check_deploy_scripts(result)
      result
    end

    def self.check_design_token_drift(result)
      result.checked!(2)
      if (drift = DesignTokens.face_root_drift?(FACE_CSS))
        result.fail(drift)
      end
      if (drift = DesignTokens.scss_anchor_drift?)
        result.fail(drift)
      end
    end
    private_class_method :check_design_token_drift

    def self.check_manifest(result)
      return check_manifest_missing(result) unless File.file?(MANIFEST)

      manifest = JSON.parse(File.read(MANIFEST))
      REQUIRED.each { |logical| check_manifest_entry(result, manifest, logical) }
    end
    private_class_method :check_manifest

    # MASTER/web/public/assets is gitignored — precompile writes it, and only
    # where something has run precompile. So its absence means two different
    # things, and this reported the harsher one everywhere: on the deploy host
    # a missing manifest is a real broken deploy, but in a fresh clone or a
    # `MASTER/bin/operator worktree` checkout it means nobody has built assets here
    # yet. That made `production` fail on arrival in any new working copy,
    # which is a gate people learn to read past — and this one guards the
    # face's assets.
    #
    # Inconclusive off the host, per the same rule the rendered gates follow:
    # a gate that measured nothing says so rather than picking a verdict.
    # GATE_STRICT_INCONCLUSIVE=1 still turns it into a failure.
    def self.check_manifest_missing(result)
      if DEPLOY_HOST_MARKERS.any? { |marker| File.exist?(marker) }
        result.fail("missing #{MANIFEST} — run: cd MASTER/web && RAILS_ENV=production bundle exec rails assets:precompile")
      else
        result.inconclusive!("MASTER/web assets not precompiled in this checkout — " \
                             "gitignored, so nothing to read until `cd MASTER/web && " \
                             "RAILS_ENV=production bundle exec rails assets:precompile` has run here")
      end
    end
    private_class_method :check_manifest_missing

    def self.check_manifest_entry(result, manifest, logical)
      result.checked!
      entry = manifest[logical]
      result.fail("manifest missing #{logical}") unless entry
      return unless entry

      digested = entry["digested_path"].to_s
      result.fail("manifest #{logical} has empty digested_path") if digested.empty?
      path = File.join(ASSETS_DIR, digested)
      result.fail("missing digested asset #{digested} for #{logical}") unless File.file?(path)
    end
    private_class_method :check_manifest_entry

    def self.check_deploy_scripts(result)
      DEPLOY_SCRIPTS.each do |relative_path, restart_mode|
        result.checked!
        path = File.join(ROOT, relative_path)
        unless File.file?(path)
          result.fail("missing MASTER web deploy script #{relative_path}")
          next
        end

        content = File.read(path)
        result.fail("#{relative_path} must precompile MASTER/web assets") unless content.include?("assets:precompile")
        # Matched on the gate name, not on a script path: the per-gate scripts at
        # the RAILS root were shims, and every caller now names the gate for
        # gates/runner.rb instead.
        runs_gate = content.match?(/gates\/runner\.rb"?\s+master_web_assets/)
        result.fail("#{relative_path} must run the master_web_assets gate") unless runs_gate

        restarts_master = content.include?("rcctl restart master")
        starts_master = content.include?("rcctl start master")
        if restart_mode == :restart
          result.fail("#{relative_path} must restart master after precompile") unless restarts_master
        elsif !restarts_master && !starts_master
          result.fail("#{relative_path} must start or restart master after precompile")
        end
      end
    end
    private_class_method :check_deploy_scripts
  end
end
