# frozen_string_literal: true

require "digest"
require "open3"
require "set"

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

    def initialize(rules:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil, incremental: false)
      @rules = rules
      @axioms = axioms
      @agent = agent
      @scanner = scanner
      @root = root
      @bus = bus
      @git = git || Reach::GitOperations.new(root)
      @learnings = learnings
      @incremental = incremental
      @violation_counts = Hash.new(0)
      @rule_recurrence = Hash.new(0)
      @preamble = build_preamble
    end

    def convergence_cfg = @convergence ||= (@axioms&.thresholds&.[]("convergence") || {})

    def max_passes_default = convergence_cfg["max_iterations"] || MAX_PASSES

    def clean_runs_required = convergence_cfg["consecutive_clean_runs_required"] || CLEAN_RUNS

    def plateau_window = convergence_cfg["stagnant_threshold"] || PLATEAU_WINDOW

    # Three guards prevent wedging when the LLM provider degrades:
    # wall-clock budget, per-pass deadline, circuit-open early-exit.
    def run(target = @root, max_passes: max_passes_default, budget_seconds: RUN_BUDGET_SECONDS, incremental: @incremental)
      files = incremental ? collect_changed_files(target) : collect_files(target)
      history = []
      seen_snapshots = Set.new
      consecutive_clean = 0
      deadline = Time.now + budget_seconds

      max_passes.times do |i|
        pass = i + 1
        if Time.now >= deadline
          @bus&.publish("fix_loop:timeout", pass:, budget_seconds:)
          return Result.ok("wall-clock timeout (#{budget_seconds}s) after #{i} pass(es)")
        end
        @bus&.publish("fix_loop:pass_start", pass:, target:)

        fast_fixed = fast_pass(files)
        commit_if_dirty("fix_loop: fast-fix [pass #{pass}]") if fast_fixed > 0

        violations = scan_violations(files)
        emit_topology(violations, target)

        if violations.empty?
          consecutive_clean += 1
          @bus&.publish("fix_loop:clean", pass:, consecutive_clean:)
          return Result.ok("clean after #{pass} pass(es)") if consecutive_clean >= clean_runs_required
          next
        end
        consecutive_clean = 0

        if stagnant?(history, seen_snapshots, violations, pass)
          break
        end

        if circuit_open?
          @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
        else
          pass_deadline = [Time.now + PASS_BUDGET_SECONDS, deadline].min
          llm_fixed = llm_pass(violations:, files:, pass:, deadline: pass_deadline)
          commit_if_dirty("fix_loop: llm-fix [pass #{pass}]") if llm_fixed > 0
          track_recurrence(violations)
        end
      end

      Result.ok("plateau or max passes reached")
    rescue StandardError => e
      @bus&.publish("fix_loop:crash", error: e.message, backtrace: e.backtrace&.first(8))
      Result.err("fix_loop: #{e.message} @ #{e.backtrace&.first(3)&.join(" | ")}", category: :unknown)
    end

    # Blocks its thread; launch via Thread.new.
    def run_forever(target = @root)
      sleep STARTUP_DELAY
      loop do
        run(target)
        @bus&.publish("fix_loop:idle", sleep: IDLE_SLEEP)
        sleep IDLE_SLEEP
      end
    rescue StandardError => e
      @bus&.publish("fix_loop:error", error: e.message)
    end

    def start_background!(target = @root)
      return Result.err("fix_loop already running") if @bg_thread&.alive?
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

    # Tier 1: rubocop -A + AstFixer + TypeChecker + DatalogEngine. No LLM.
    def fast_pass(files)
      fixed = 0
      rb = files.select { |f| f.end_with?(".rb") }
      if rb.any?
        _, status = Open3.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", "-q", *rb, chdir: @root)
        fixed += rb.size if status.success?
      end
      rb.each do |path|
        next unless File.exist?(path)
        fixed += analyze_ruby_file(path)
      rescue StandardError => e
        @bus&.publish("fix_loop:fast_error", file: path, error: e.message)
      end
      fixed
    end

    # Tier 2: one RuleLoop pass per rule, highest-priority rules first.
    # Bails early if the deadline passes or the LLM circuit opens mid-pass.
    def llm_pass(violations:, files:, pass:, deadline: nil)
      fixed = 0
      ordered_rules.each do |rule|
        next unless violations.any? { |v| v[:rule] == rule.id }
        if deadline && Time.now >= deadline
          @bus&.publish("fix_loop:pass_timeout", pass:, rule_skipped: rule.id)
          break
        end
        if circuit_open?
          @bus&.publish("fix_loop:llm_skipped", pass:, rule_skipped: rule.id, reason: "circuit_open")
          break
        end
        rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root,
                          bus: @bus, learnings: @learnings)
        rl.injected_preamble = @preamble
        result = rl.run_once(files)
        @violation_counts[rule.id] += result[:fixed]
        fixed += result[:fixed]
        @bus&.publish("fix_loop:rule_result", pass:, rule: rule.id, **result)
      end
      fixed
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
      breaker = @agent.respond_to?(:circuit_breaker) ? @agent.circuit_breaker : nil
      return false unless breaker.respond_to?(:open_models)
      !breaker.open_models.empty?
    rescue StandardError
      false
    end

    def open_breakers
      @agent.respond_to?(:circuit_breaker) ? Array(@agent.circuit_breaker&.open_models) : []
    rescue StandardError
      []
    end

    def scan_violations(files)
      files.flat_map do |path|
        next [] unless File.exist?(path)
        result = @scanner.scan(path)
        Result.wrap(result).value_or([]).map { |v| v.to_h.merge(file: path.delete_prefix("#{@root}/")) }
      end
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
      rules = @rules.sort_by do |r|
        base_prior = priors.dig(r.id, "prior_p").to_f
        modifiers = priors.dig(r.id, "language_modifiers") || {}
        adjusted = ext_wts.sum { |ext, w| base_prior * (modifiers[ext] || 1.0) * w }
        density = @violation_counts[r.id].to_f + adjusted
        quality = @learnings&.fix_quality(rule: r.id) || 0.5
        [-density, -quality]
      end
      topo_sort(rules, deps)
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
      soul = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
      abs = soul.fetch("absolute", {})
      golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      lines = ["Golden rule: #{golden}",
               "Minimum change that eliminates the violation. Do not touch unrelated code."]
      abs.fetch("code_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
      abs.fetch("aesthetic_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
      lines.join("\n")
    rescue StandardError
      "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
    end

    def collect_files(target)
      Dir.glob(File.join(target, "**", "*"))
         .select { |f| File.file?(f) }
         .reject { |f| SKIP_DIRS.any? { |d| f.include?(d) } }
         .sort
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
         .reject { |f| SKIP_DIRS.any? { |d| f.include?(d) } }
         .sort
    end

    def commit_if_dirty(msg)
      return unless @git&.dirty?(".")
      @git.add_all
      @git.commit(msg)
    rescue StandardError => e
      @bus&.publish("fix_loop:commit_error", error: e.message)
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

    # Returns true and publishes an event when oscillation or plateau is detected.
    def stagnant?(history, seen_snapshots, violations, pass)
      snap = violation_snapshot(violations)
      if seen_snapshots.include?(snap)
        @bus&.publish("fix_loop:oscillation", pass:, violations: violations.size)
        return true
      end
      seen_snapshots << snap
      history << violations.size
      window = plateau_window
      if history.size >= window && history.last(window).uniq.size == 1
        @bus&.publish("fix_loop:plateau", pass:, violations: violations.size)
        return true
      end
      false
    end

    def violation_snapshot(violations)
      key = violations.map { |v| "#{v[:rule]}:#{v[:file]}:#{v[:line].to_i}" }.sort.join("|")
      Digest::SHA256.hexdigest(key)
    end
  end
  end
end
