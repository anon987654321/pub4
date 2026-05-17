# frozen_string_literal: true

require "open3"

module Master
  module Loop
  # Two-tier act-react loop — architectures #1, #2, #3, #14, #15.
  #
  # Each pass:
  #   Tier 1 (fast)  — rubocop -A + AstFixer; no LLM; instant.
  #   Tier 2 (LLM)   — one RuleLoop pass per rule, ordered by priority.
  #
  # Stops when violations reach zero (2 consecutive clean passes) or plateau.
  # run_forever wraps run in an idle-sleep loop for the background daemon.
  class SuperLoop
    IDLE_SLEEP      = 300
    STARTUP_DELAY   = 90
    MAX_PASSES      = 12
    PLATEAU_WINDOW  = 2
    SKIP_DIRS       = %w[vendor/ knowledge/ node_modules/ .git/ .bundle/ tmp/ log/ dist/].freeze
    DEPS_PATH       = File.join(Master::ROOT, "data", "rule_deps.yml").freeze
    PRIORS_PATH     = File.join(Master::ROOT, "data", "violation_priors.yml").freeze

    def initialize(rules:, agent:, scanner:, root:, bus: nil, git: nil, learnings: nil)
      @rules            = rules
      @agent            = agent
      @scanner          = scanner
      @root             = root
      @bus              = bus
      @git              = git || Reach::GitOperations.new(root)
      @learnings        = learnings
      @violation_counts = Hash.new(0)
      @rule_recurrence  = Hash.new(0)
      @preamble         = build_preamble
    end

    # Bounded convergence loop — used by /fix and run_forever.
    def run(target = @root, max_passes: MAX_PASSES)
      files             = collect_files(target)
      history           = []
      consecutive_clean = 0

      max_passes.times do |i|
        pass = i + 1
        @bus&.publish("super_loop:pass_start", pass:, target:)

        # Tier 1 — fast: rubocop -A + AstFixer, no LLM
        fast_fixed = fast_pass(files)
        commit_if_dirty("super_loop: fast-fix [pass #{pass}]") if fast_fixed > 0

        violations = scan_violations(files)
        emit_topology(violations, target)

        if violations.empty?
          consecutive_clean += 1
          @bus&.publish("super_loop:clean", pass:, consecutive_clean:)
          return Result.ok("clean after #{pass} pass(es)") if consecutive_clean >= 2
          next
        end
        consecutive_clean = 0

        history << violations.size
        if history.size >= PLATEAU_WINDOW && history.last(PLATEAU_WINDOW).uniq.size == 1
          @bus&.publish("super_loop:plateau", pass:, violations: violations.size)
          break
        end

        # Tier 2 — LLM: one pass per rule in priority order
        llm_fixed = llm_pass(violations, files, pass)
        commit_if_dirty("super_loop: llm-fix [pass #{pass}]") if llm_fixed > 0
        track_recurrence(violations)
      end

      Result.ok("plateau or max passes reached")
    rescue StandardError => e
      Result.err("super_loop: #{e.message}", category: :unknown)
    end

    # Background daemon — blocks its thread. Launch via Thread.new.
    def run_forever(target = @root)
      sleep STARTUP_DELAY
      loop do
        run(target)
        @bus&.publish("super_loop:idle", sleep: IDLE_SLEEP)
        sleep IDLE_SLEEP
      end
    rescue StandardError => e
      @bus&.publish("super_loop:error", error: e.message)
    end

    private

    # Tier 1: rubocop -A on .rb files + AstFixer transforms. No LLM.
    def fast_pass(files)
      fixed  = 0
      rb     = files.select { |f| f.end_with?(".rb") }
      if rb.any? && system("bundle", "exec", "rubocop", "-A", "--no-color", "-q", *rb,
                           out: File::NULL, err: File::NULL, chdir: @root)
        fixed += rb.size
      end
      rb.each do |path|
        next unless File.exist?(path)
        src    = File.read(path, encoding: "UTF-8")
        result = Judge::Scan::AstFixer.fix(path, src)
        next unless result&.changed
        fixed += result.transforms.size
        @bus&.publish("super_loop:ast_fixed", file: path.delete_prefix("#{@root}/"), transforms: result.transforms)
      rescue StandardError => e
        @bus&.publish("super_loop:fast_error", file: path, error: e.message)
      end
      fixed
    end

    # Tier 2: one RuleLoop pass per rule, highest-priority rules first.
    def llm_pass(violations, files, pass)
      fixed = 0
      ordered_rules.each do |rule|
        next unless violations.any? { |v| v[:rule] == rule.id }
        rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root,
                          bus: @bus, learnings: @learnings)
        rl.injected_preamble = @preamble
        result = rl.run_once(files)
        @violation_counts[rule.id] += result[:fixed]
        fixed += result[:fixed]
        @bus&.publish("super_loop:rule_result", pass:, rule: rule.id, **result)
      end
      fixed
    end

    def scan_violations(files)
      files.flat_map do |path|
        next [] unless File.exist?(path)
        result = @scanner.scan(path)
        Result.wrap(result).value_or([]).map { |v| v.merge(file: path.delete_prefix("#{@root}/")) }
      end
    end

    # Soul learning — flag rules recurring across 3+ consecutive passes.
    def track_recurrence(violations)
      tally = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
      tally.each do |rule_id, _|
        @rule_recurrence[rule_id] += 1
        next unless @rule_recurrence[rule_id] >= 3
        @rule_recurrence.delete(rule_id)
        sample = violations.select { |v| v[:rule].to_s == rule_id }.first(5)
        @bus&.publish("super_loop:soul_proposal", rule: rule_id, sample:)
        append_improvement(rule_id, sample)
      end
      (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
    end

    def append_improvement(rule_id, sample)
      path = File.join(@root, "runtime", "improvements.md")
      FileUtils.mkdir_p(File.dirname(path))
      files = sample.map { |v| v[:file] }.uniq.first(3).join(", ")
      File.open(path, "a") { |f| f.write("#{Time.now.utc.strftime("%Y-%m-%d %H:%M")} #{rule_id}: recurring in #{files}\n") }
    rescue StandardError
      nil
    end

    # Architecture #1 + #2 + #14: density + topological + Bayesian ordering.
    def ordered_rules
      deps   = load_deps
      priors = load_priors
      rules  = @rules.sort_by { |r| -(@violation_counts[r.id].to_f + priors.dig(r.id, "prior_p").to_f) }
      topo_sort(rules, deps)
    end

    # Architecture #15: emit module-grouped topology for particle visualisation.
    def emit_topology(violations, target)
      by_mod = violations.group_by { |v| v[:file].to_s.split("/").first(3).join("/") }
                         .transform_values(&:size)
      @bus&.publish("codebase:topology", {
        timestamp:        Time.now.utc.iso8601,
        target:           target.delete_prefix("#{@root}/"),
        total_violations: violations.size,
        any_dirty:        violations.any?,
        modules:          by_mod.map { |path, count| { path:, violations: count } }
      })
    end

    # Architecture #2: Kahn's topological sort on rule dependency graph.
    def topo_sort(rules, deps)
      id_map = rules.index_by(&:id)
      in_deg = Hash.new(0)
      adj    = Hash.new { |h, k| h[k] = [] }
      rules.each do |rule|
        (deps[rule.id] || []).each do |dep_id|
          next unless id_map[dep_id]
          adj[dep_id] << rule.id
          in_deg[rule.id] += 1
        end
      end
      queue  = rules.select { |r| in_deg[r.id].zero? }.map(&:id)
      sorted = []
      until queue.empty?
        id = queue.shift
        sorted << id_map[id]
        adj[id].each { |nxt| in_deg[nxt] -= 1; queue << nxt if in_deg[nxt].zero? }
      end
      sorted + (rules - sorted)
    end

    def build_preamble
      soul   = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
      abs    = soul.fetch("absolute", {})
      golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      lines  = ["Golden rule: #{golden}",
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

    def commit_if_dirty(msg)
      return unless @git&.dirty?(".")
      @git.add_lib_files
      @git.commit(msg)
    rescue StandardError => e
      @bus&.publish("super_loop:commit_error", error: e.message)
    end

    def load_deps
      data = Master.load_yaml(DEPS_PATH)
      (data&.dig("deps") || {}).transform_values { |v| Array(v["after"] || []) }
    rescue StandardError
      {}
    end

    def load_priors
      Master.load_yaml(PRIORS_PATH) || {}
    rescue StandardError
      {}
    end
  end
  end
end
