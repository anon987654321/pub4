# frozen_string_literal: true

require "digest"
require "open3"
require "set"
require "time"
require_relative "fix_loop/committer"
require_relative "fix_loop/llm_router"
require_relative "fix_loop/scanner"
require_relative "severity"
require_relative "violation"

module Master
  module Loop
  # Two-tier act-react loop — architectures #1, #2, #3, #14, #15.
    class FixLoop
      IDLE_SLEEP = 300
      STARTUP_DELAY = 90
      MAX_PASSES = 15
      CLEAN_RUNS = 2
      PLATEAU_WINDOW = 3
      RUN_BUDGET_SECONDS = 30 * 60
      PASS_BUDGET_SECONDS = 8 * 60
      SKIP_DIRS = %w[vendor/ knowledge/ node_modules/ .git/ .bundle/ tmp/ log/ dist/].freeze
      DEPS_PATH = File.join(Master::ROOT, "data", "rule_deps.yml").freeze
      PRIORS_PATH = File.join(Master::ROOT, "data", "violation_priors.yml").freeze
      WORKFLOW_PATH = File.join(Master::ROOT, "data", "workflow.yml").freeze
      TIER2_QUALITY_RULE_IDS = %w[DRY KISS SRP].freeze
      PassResult = Struct.new(:status, :message, :consecutive_clean, keyword_init: true)

      def initialize(rules:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil, incremental: false)
        @rules = rules
        @axioms = axioms
        @agent = agent
        @scanner = scanner
        @root = root
        @bus = bus
        @git = git || Reach::GitOperations.new(root)
        @committer = Committer.new(git: @git, bus: bus)
        @loop_scanner = Scanner.new(scanner: scanner, root: root, bus: bus)
        @llm_router = LlmRouter.new(agent)
        @learnings = learnings
        @incremental = incremental
        @violation_counts = Hash.new(0)
        @rule_recurrence = Hash.new(0)
        @halted = false
        @halt_reason = nil
        @preamble = build_preamble
      end

      def convergence_cfg = @convergence ||= (@axioms&.thresholds&.[]("convergence") || {})

      def max_passes_default = convergence_cfg["max_iterations"] || MAX_PASSES

      def clean_runs_required = convergence_cfg["consecutive_clean_runs_required"] || CLEAN_RUNS

      def plateau_window = convergence_cfg["stagnant_threshold"] || PLATEAU_WINDOW

      def max_cycles_default = workflow_cfg.dig("autoloop", "max_cycles") || max_passes_default

      def startup_delay_default = workflow_cfg.dig("autoloop", "startup_delay") || STARTUP_DELAY

      def idle_sleep_default = workflow_cfg.dig("autoloop", "idle_sleep") || IDLE_SLEEP

      # Three guards prevent wedging when the LLM provider degrades:
      # wall-clock budget, per-pass deadline, circuit-open early-exit.
      def run(target = @root, max_passes: max_passes_default, budget_seconds: RUN_BUDGET_SECONDS, incremental: @incremental)
        return halted_result if halted?

        files = incremental ? collect_changed_files(target) : collect_files(target)
        history = []
        seen_snapshots = Set.new
        recurring_violations = Hash.new(0)
        consecutive_clean = 0
        deadline = Time.now + budget_seconds

        max_passes.times do |i|
          pass = i + 1
          if Time.now >= deadline
            @bus&.publish("fix_loop:timeout", pass:, budget_seconds:)
            return Result.ok("wall-clock timeout (#{budget_seconds}s) after #{i} pass(es)")
          end

          result = run_pass(files: files, target: target, pass: pass, deadline: deadline,
                            history: history, seen_snapshots: seen_snapshots,
                            recurring_violations: recurring_violations,
                            consecutive_clean: consecutive_clean)
          consecutive_clean = result.consecutive_clean
          return Result.ok(result.message) if result.status == :clean
          break if result.status == :plateau
        end

        Result.ok("plateau or max passes reached")
      rescue StandardError => e
        @bus&.publish("fix_loop:crash", error: e.message, backtrace: e.backtrace&.first(8))
        Result.err("fix_loop: #{e.message} @ #{e.backtrace&.first(3)&.join(" | ")}", category: :unknown)
      end

      def run_forever(target = @root, max_cycles: max_cycles_default, startup_delay: startup_delay_default,
                      idle_sleep: idle_sleep_default, cooldown_sleep: idle_sleep_default)
        sleep startup_delay
        cycles = 0
        while cycles < max_cycles
          break if halted?
          cycles += 1
          run(target)
          break if halted?
          @bus&.publish("fix_loop:idle", sleep: idle_sleep, cycle: cycles, max_cycles:)
          sleep idle_sleep
        rescue StandardError => e
          @bus&.publish("fix_loop:error", error: e.message, cycle: cycles, max_cycles:)
          sleep cooldown_sleep
        end
        @bus&.publish("fix_loop:max_cycles", cycles:, max_cycles:) unless halted?
      end

      def start_background!(target = @root)
        return Result.err("fix_loop already running") if @bg_thread&.alive?
        @halted = false
        @halt_reason = nil
        @bg_thread = Thread.new { run_forever(target) }
        @bg_thread.abort_on_exception = false
        @bus&.publish("fix_loop:background_start", target:)
        Result.ok("fix_loop background started")
      end

      def stop_background!
        return Result.err("fix_loop not running") unless @bg_thread&.alive?
        @bg_thread.kill
        @bg_thread = nil
        @bus&.publish("fix_loop:background_stop")
        Result.ok("fix_loop background stopped")
      end

      def background_alive? = @bg_thread&.alive? || false

      def halt!(reason: "self_violation")
        @halted = true
        @halt_reason = reason
        @bg_thread&.kill if @bg_thread&.alive?
        @bg_thread = nil
        @bus&.publish("fix_loop:halt", reason:)
        Result.ok("fix_loop halted: #{reason}")
      end

      def halted? = @halted

      # Scan only — no commit, no mutation. Always full scan regardless of incremental flag.
      def preview(target = @root)
        files = collect_files(target)
        violations = scan_violations(files)
        by_rule = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
        by_file = violations.group_by { |v| v[:file].to_s }.transform_values(&:size)
        Result.ok(
          total: violations.size,
          rules: by_rule.sort_by { |_, n| -n }.first(10).to_h,
          files: by_file.sort_by { |_, n| -n }.first(10).to_h
        )
      end

      private

      def run_pass(files:, target:, pass:, deadline:, history:, seen_snapshots:, recurring_violations:, consecutive_clean:)
        pass_mtimes = file_mtimes(files)
        @bus&.publish("fix_loop:pass_start", pass:, target:, file_count: files.size)

        fast_fixed = run_fast_stage(files, pass)
        violations = run_scan_stage(files, target)
        return handle_clean_pass(files, pass_mtimes, pass, consecutive_clean) if violations.empty?
        return PassResult.new(status: :plateau, consecutive_clean: 0) if stagnant?(history, seen_snapshots, recurring_violations, violations, pass)

        run_llm_stage(violations, files, pass, deadline)
        PassResult.new(status: :continue, consecutive_clean: 0)
      end

      def run_fast_stage(files, pass)
        fast_fixed = fast_pass(files)
        @committer.commit_if_dirty("fix_loop: fast-fix [pass #{pass}]") if fast_fixed > 0
        fast_fixed
      end

      def run_scan_stage(files, target)
        scan_violations(files).tap { |violations| emit_topology(violations, target) }
      end

      def run_llm_stage(violations, files, pass, deadline)
        if circuit_open?
          @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
          return 0
        end

        pass_deadline = [Time.now + PASS_BUDGET_SECONDS, deadline].min
        llm_fixed = llm_pass(violations:, files:, pass:, deadline: pass_deadline)
        @committer.commit_if_dirty("fix_loop: llm-fix [pass #{pass}]") if llm_fixed > 0
        track_recurrence(violations)
        llm_fixed
      end

      def handle_clean_pass(files, pass_mtimes, pass, consecutive_clean)
        ground_truth = ground_truth_violations(files)
        unless ground_truth.empty?
          @bus&.publish("fix_loop:ground_truth_failed", pass:, violations: ground_truth.size)
          return PassResult.new(status: :continue, consecutive_clean: 0)
        end

        @bus&.publish("fix_loop:ground_truth_ok", pass:)
        unless files_quiescent?(files, pass_mtimes)
          @bus&.publish("fix_loop:quiesce_wait", pass:)
          return PassResult.new(status: :continue, consecutive_clean: 0)
        end

        clean_count = consecutive_clean + 1
        @bus&.publish("fix_loop:clean", pass:, consecutive_clean: clean_count)
        status = clean_count >= clean_runs_required ? :clean : :continue
        PassResult.new(status: status, message: "clean after #{pass} pass(es)", consecutive_clean: clean_count)
      end

      def halted_result
        Result.err("fix_loop halted: #{@halt_reason || "self_violation"}", category: :policy)
      end

      # Tier 1: rubocop -A + AstFixer + TypeChecker + DatalogEngine. No LLM.
      def fast_pass(files)
        fixed = 0
        rb = files.select { |f| f.end_with?(".rb") }
        if rb.any?
          _, status = Open3.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", "-q", *rb, chdir: @root)
          fixed += status.success? ? rb.size : rubocop_each_file(rb)
        end
        rb.each do |path|
          next unless File.exist?(path)
          fixed += analyze_ruby_file(path)
        rescue StandardError => e
          @bus&.publish("fix_loop:fast_error", file: path, error: e.message)
        end
        fixed
      end

      def rubocop_each_file(files)
        files.count do |path|
          _, status = Open3.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", "-q", path, chdir: @root)
          @bus&.publish("fix_loop:rubocop_file_failed", file: path) unless status.success?
          status.success?
        end
      end

      # Tier 2: one RuleLoop pass per rule, highest-priority rules first.
      # Bails early if the deadline passes or the LLM circuit opens mid-pass.
      def llm_pass(violations:, files:, pass:, deadline: nil)
        fixed = 0
        rule_violations = violations.group_by { |v| v[:rule].to_s }
        runnable = ordered_rules.select { |rule| rule_violations.key?(rule.id.to_s) }
        dependency_levels(runnable).each do |group|
          break if deadline && Time.now >= deadline
          break if circuit_open?

          results = run_rule_group(group:, files:, pass:, rule_violations:)
          results.each do |rule, result|
            @violation_counts[rule.id] += result[:fixed]
            fixed += result[:fixed]
            @bus&.publish("fix_loop:rule_result", pass:, rule: rule.id, **result)
          end
        end
        if deadline && Time.now >= deadline
          @bus&.publish("fix_loop:pass_timeout", pass:)
        elsif circuit_open?
          @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
        end
        fixed
      end

      def run_rule_group(group:, files:, pass:, rule_violations:)
        return group.map { |rule| [rule, run_rule_once(rule, files, pass)] } unless disjoint_rule_files?(group, rule_violations)

        group.map do |rule|
          Thread.new { [rule, run_rule_once(rule, files, pass)] }
        end.map(&:value)
      end

      def run_rule_once(rule, files, pass)
        rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root,
                          bus: @bus, learnings: @learnings)
        rl.injected_preamble = @preamble
        @bus&.publish("fix_loop:tier2_quality_route", pass:, rule: rule.id) if tier2_quality_rule?(rule.id)
        rl.run_once(files)
      end

      def disjoint_rule_files?(rules, rule_violations)
        seen = Set.new
        rules.all? do |rule|
          files = Array(rule_violations[rule.id.to_s]).map { |v| v[:file].to_s }.uniq
          overlap = files.any? { |file| seen.include?(file) }
          files.each { |file| seen << file }
          !overlap
        end
      end

      def dependency_levels(rules)
        deps = load_deps
        remaining = rules.map(&:id).to_set
        id_map = rules.to_h { |rule| [rule.id, rule] }
        levels = []
        until remaining.empty?
          ready = remaining.select { |id| Array(deps[id]).none? { |dep| remaining.include?(dep) } }
          ready = [remaining.first] if ready.empty?
          levels << ready.map { |id| id_map[id] }.compact
          ready.each { |id| remaining.delete(id) }
        end
        levels
      end

      # AST-fix, type-check, and datalog-evaluate one Ruby file. Returns fix count.
      def analyze_ruby_file(path)
        src = File.read(path, encoding: "UTF-8")
        fixed = 0
        rel = path.delete_prefix("#{@root}/")

        ast_result = Judge::Scan::AstFixer.fix(path, src)
        if ast_result&.changed
          fixed += ast_result.transforms.size
          @bus&.publish("fix_loop:ast_fixed", file: rel, transforms: ast_result.transforms)
          src = File.read(path, encoding: "UTF-8")
        end

        Ground::TypeChecker.check(path, src).each do |te|
          @bus&.publish("fix_loop:type_error", file: rel, rule: te.rule, message: te.message)
        end

        dl = Judge::Scan::DatalogEngine.from_ruby(path, src)
        dl.rule(:BARE_RESCUE_DATALOG, :bare_rescue) { |f| "bare rescue at line #{f.args[1]} — use rescue StandardError" }
        dl.evaluate.each do |finding|
          @bus&.publish("fix_loop:datalog_finding", file: rel, rule: finding.rule_id, message: finding.message)
        end

        fixed
      end

      def circuit_open?
        @llm_router.circuit_open?
      end

      def open_breakers
        @llm_router.open_breakers
      end

      def scan_violations(files)
        @loop_scanner.violations(files)
      end

      def ground_truth_violations(files)
        files.each { |path| File.read(path, encoding: "UTF-8") if File.file?(path) }
        scan_violations(files)
      end

      def file_mtimes(files)
        files.to_h { |path| [path, File.exist?(path) ? File.mtime(path).to_f : nil] }
      end

      def files_quiescent?(files, before)
        file_mtimes(files) == before
      rescue StandardError => e
        false
      end

      # Flag rules recurring across 3+ consecutive passes for soul proposals.
      def track_recurrence(violations)
        tally = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
        tally.each do |rule_id, _|
          @rule_recurrence[rule_id] += 1
          next unless @rule_recurrence[rule_id] >= 3
          @rule_recurrence.delete(rule_id)
          sample = violations.select { |v| v[:rule].to_s == rule_id }.first(5)
          @bus&.publish("fix_loop:soul_proposal", rule: rule_id, sample:)
          append_improvement(rule_id, sample)
        end
        (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
      end

      def append_improvement(rule_id, sample)
        files = sample.map { |v| v[:file] }.uniq.first(3).join(", ")
        @bus&.publish("loop:recurrence", rule: rule_id, files:, at: Time.now.utc.iso8601)
        path = File.join(@root, "runtime", "improvements.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{Time.now.utc.strftime("%Y-%m-%d %H:%M")} #{rule_id}: recurring in #{files}\n",
                   mode: "a")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.append_improvement", event_bus: @bus, rule_id:)
      end

      # Density + fix_quality + language-adjusted Bayesian + topological — architectures #1, #2, #10, #14.
      def ordered_rules
        deps = load_deps
        priors = load_priors
        ext_wts = extension_weights(@root)
        rules = @rules.each_with_index.sort_by do |r, i|
          base_prior = priors.dig(r.id, "prior_p").to_f
          modifiers = priors.dig(r.id, "language_modifiers") || {}
          adjusted = ext_wts.sum { |ext, w| base_prior * (modifiers[ext] || 1.0) * w }
          density = @violation_counts[r.id].to_f + adjusted
          quality = @learnings&.fix_quality(rule: r.id) || 0.5
          tier2_priority = tier2_quality_rule?(r.id) ? 1 : 0
          [-tier2_priority, -density, -quality, i]
        end.map(&:first)
        topo_sort(rules, deps)
      end

      def tier2_quality_rule?(rule_id)
        TIER2_QUALITY_RULE_IDS.include?(rule_id.to_s)
      end

      # Emit module-grouped topology for particle visualisation — architecture #15.
      def emit_topology(violations, target)
        by_mod = violations.group_by { |v| v[:file].to_s.split("/").first(3).join("/") }
                           .transform_values(&:size)
        @bus&.publish("codebase:topology", {
          timestamp: Time.now.utc.iso8601,
          target: target.delete_prefix("#{@root}/"),
          total_violations: violations.size,
          any_dirty: violations.any?,
          modules: by_mod.map { |path, count| { path:, violations: count } }
        })
      end

      # Kahn's topological sort on rule dependency graph — architecture #2.
      def topo_sort(rules, deps)
        id_map = rules.to_h { |r| [r.id, r] }
        in_deg = Hash.new(0)
        adj = Hash.new { |h, k| h[k] = [] }
        rules.each do |rule|
          (deps[rule.id] || []).each do |dep_id|
            next unless id_map[dep_id]
            adj[dep_id] << rule.id
            in_deg[rule.id] += 1
          end
        end
        queue = rules.select { |r| in_deg[r.id].zero? }.map(&:id)
        sorted = []
        until queue.empty?
          id = queue.shift
          sorted << id_map[id]
          adj[id].each { |nxt| in_deg[nxt] -= 1; queue << nxt if in_deg[nxt].zero? }
        end
        sorted + (rules - sorted)
      end

      def build_preamble
        self.class.preamble_from_soul
      end

      def self.preamble_from_soul
        path = File.join(Master::ROOT, "data", "soul.yml")
        mtime = File.mtime(path).to_i
        return @preamble_cache[:value] if @preamble_cache && @preamble_cache[:mtime] == mtime

        soul = Master.load_yaml(path)
        abs = soul.fetch("absolute", {})
        golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        lines = ["Golden rule: #{golden}",
                 "Minimum change that eliminates the violation. Do not touch unrelated code."]
        abs.fetch("code_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
        abs.fetch("aesthetic_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
        @preamble_cache = { mtime:, value: lines.join("\n") }
        @preamble_cache[:value]
      rescue StandardError => e
        "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end

      def collect_files(target)
        tracked = collect_tracked_files(target)
        return tracked unless tracked.empty?

        Dir.glob(File.join(target, "**", "*"))
           .select { |f| File.file?(f) }
           .reject { |f| skipped_path?(f) }
           .sort
      end

      def collect_tracked_files(target)
        out, _, status = Open3.capture3("git", "-C", @root, "ls-files", "-z")
        return [] unless status.success?

        out.split("\0").map { |rel| File.join(@root, rel) }
           .select { |file| File.file?(file) && under_path?(file, target) }
           .reject { |file| skipped_path?(file) }
           .sort
      rescue StandardError => e
        []
      end

      def skipped_path?(path)
        SKIP_DIRS.any? { |dir| path.include?(dir) } || binary_file?(path)
      end

      def binary_file?(path)
        File.file?(path) && File.binary?(path)
      rescue StandardError => e
        true
      end

      def under_path?(path, root)
        expanded_path = File.expand_path(path)
        expanded_root = File.expand_path(root)
        expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
      end

      def collect_changed_files(target)
        changed = changed_since_last_commit(target)
        return collect_files(target) if changed.empty?
        changed
      rescue StandardError => e
        @bus&.publish("fix_loop:incremental_fallback", error: e.message)
        collect_files(target)
      end

      def changed_since_last_commit(target)
        out, _, status = Open3.capture3("git", "-C", @root, "diff", "--name-only", "HEAD")
        return [] unless status.success?
        out.lines.map(&:strip).reject(&:empty?)
           .map { |rel| File.join(@root, rel) }
           .select { |f| File.exist?(f) && f.start_with?(target) }
           .reject { |f| skipped_path?(f) }
           .sort
      end

      # Fractional weight per extension; used by ordered_rules to apply language_modifiers.
      def extension_weights(target)
        counts = Hash.new(0)
        collect_files(target).each do |f|
          ext = File.extname(f).delete(".").downcase
          counts[ext] += 1 unless ext.empty?
        end
        total = counts.values.sum.to_f
        return {} if total.zero?
        counts.transform_values { |n| n / total }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.extension_weights", event_bus: @bus)
        {}
      end

      def load_deps
        data = Master.load_yaml(DEPS_PATH)
        (data&.dig("deps") || {}).transform_values { |v| Array(v["after"] || []) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.load_deps", event_bus: @bus)
        {}
      end

      def load_priors
        Master.load_yaml(PRIORS_PATH) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.load_priors", event_bus: @bus)
        {}
      end

      def workflow_cfg
        @workflow_cfg ||= Master.load_yaml(WORKFLOW_PATH) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.workflow_cfg", event_bus: @bus)
        {}
      end

      # Returns true and publishes an event when oscillation or plateau is detected.
      def stagnant?(history, seen_snapshots, recurring_violations, violations, pass)
        snap = violation_snapshot(violations)
        if seen_snapshots.include?(snap)
          @bus&.publish("fix_loop:oscillation", pass:, violations: violations.size)
          return true
        end
        seen_snapshots << snap

        recurring = recurring_violation(violations, recurring_violations)
        if recurring
          @bus&.publish("fix_loop:cycle_detected", pass:, threshold: plateau_window, violation: recurring)
          return true
        end

        history << violations.size
        window = plateau_window
        if history.size >= window && history.last(window).uniq.size == 1
          @bus&.publish("fix_loop:plateau", pass:, violations: violations.size)
          return true
        end
        false
      end

      def recurring_violation(violations, recurring_violations)
        current = violations.to_h { |violation| [violation_key(violation), violation] }
        (recurring_violations.keys - current.keys).each { |key| recurring_violations.delete(key) }
        current.each do |key, violation|
          recurring_violations[key] += 1
          return violation if recurring_violations[key] >= plateau_window
        end
        nil
      end

      def violation_snapshot(violations)
        key = violations.map { |violation| violation_key(violation) }.sort.join("|")
        Digest::SHA256.hexdigest(key)
      end
