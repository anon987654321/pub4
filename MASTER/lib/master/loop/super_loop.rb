# frozen_string_literal: true

require "open3"

module Master
  module Loop
  # Act-react superloop — implements architectures #1, #2, #3, #15.
  #
  # Inner loops: one RuleLoop per rule, run to convergence.
  # Outer loop:  runs all inner loops, itself autoloops indefinitely.
  # Strategy:    :rule_first (default) or :file_first (#3).
  # Ordering:    priority queue by recent violation density (#1) +
  #              topological sort from data/rule_deps.yml (#2).
  # Topology:    emits codebase:topology SSE event after each pass (#15)
  #              so the particle system can render live codebase state.
  class SuperLoop
    # 300s between clean passes; 90s before first self-run after boot.
    IDLE_SLEEP     = 300
    STARTUP_DELAY  = 90
    SCAN_GLOB      = Master::Judge::Scan::Scanner::SCAN_GLOB
    SKIP_DIRS      = %w[vendor/ knowledge/ node_modules/ .git/ .bundle/ tmp/ log/ dist/].freeze
    GIT_COMMIT_MSG = "super_loop: autofix violations".freeze
    DEPS_PATH      = File.join(Master::ROOT, "data", "rule_deps.yml").freeze

    def initialize(rules:, agent:, scanner:, root:, bus: nil, git: nil)
      @rules        = rules
      @agent        = agent
      @scanner      = scanner
      @root         = root
      @bus          = bus
      @git          = git || Reach::GitOperations.new(root)
      # rule_id → cumulative violations seen across passes
      @violation_counts = Hash.new(0)
    end

    # One-shot: run all rule loops once against target.
    # strategy: :rule_first | :file_first
    def run_once(target = @root, strategy: :rule_first)
      files = collect_files(target)
      strategy == :file_first ? pass_file_first(files) : pass_rule_first(files)
    end

    # Continuous: run forever. Sleeps IDLE_SLEEP when clean, retries immediately when dirty.
    # Launch via Thread.new — this blocks its thread.
    def run_forever(target = @root)
      sleep STARTUP_DELAY
      loop do
        result    = run_once(target)
        any_dirty = result[:rule_results].any? { |r| r[:status] != :clean }
        emit_topology(result[:rule_results], target)
        @bus&.publish("super_loop:pass", target:, any_dirty:,
                      rules: result[:rule_results].size,
                      fixed: result[:rule_results].sum { |r| r[:fixed] })
        if any_dirty
          commit_if_dirty
        else
          @bus&.publish("super_loop:idle", sleep: IDLE_SLEEP)
          sleep IDLE_SLEEP
        end
      end
    rescue StandardError => e
      @bus&.publish("super_loop:error", error: e.message)
      Result.err("super_loop: #{e.message}", category: :unknown)
    end

    private

    # Architecture #1 + #2: priority queue + topological ordering.
    def ordered_rules
      deps  = load_deps
      rules = @rules.sort_by { |r| -@violation_counts[r.id] }
      topo_sort(rules, deps)
    end

    # Architecture #3 (rule-first default): converge each rule across all files.
    def pass_rule_first(files)
      rule_results = ordered_rules.map do |rule|
        rl     = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus)
        result = rl.run(files)
        @violation_counts[rule.id] += result[:fixed]
        @bus&.publish("super_loop:rule_result", rule: rule.id, **result)
        result.merge(rule: rule.id)
      end
      { rule_results: }
    end

    # Architecture #3 (file-first): converge all rules on one file before next.
    def pass_file_first(files)
      rule_results_by_rule = Hash.new { |h, k| h[k] = { fixed: 0, cycles: 0, status: :clean, rule: k } }
      files.each do |path|
        ordered_rules.each do |rule|
          rl     = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus)
          result = rl.run([path])
          @violation_counts[rule.id] += result[:fixed]
          agg = rule_results_by_rule[rule.id]
          agg[:fixed]  += result[:fixed]
          agg[:cycles] += result[:cycles]
          agg[:status]  = result[:status] if result[:status] != :clean
        end
      end
      { rule_results: rule_results_by_rule.values }
    end

    # Architecture #15: emit codebase topology for particle visualization.
    def emit_topology(rule_results, target)
      modules   = group_by_module(rule_results, target)
      timestamp = Time.now.utc.iso8601
      @bus&.publish("codebase:topology", {
        timestamp:        timestamp,
        target:           target.delete_prefix(@root + "/"),
        total_violations: rule_results.sum { |r| r[:fixed] },
        any_dirty:        rule_results.any? { |r| r[:status] != :clean },
        modules:          modules
      })
    end

    def group_by_module(rule_results, target)
      # Map rules to module paths based on known structure.
      module_map = {}
      @rules.each do |rule|
        class_name = rule.class.name.to_s
        mod = class_name.split("::")[0..2].join("::").downcase.gsub("::", "/")
        module_map[rule.id] = mod
      end
      by_mod = Hash.new { |h, k| h[k] = { path: k, violations: 0, rules: [], status: :clean } }
      rule_results.each do |r|
        mod = module_map[r[:rule]] || "unknown"
        entry = by_mod[mod]
        entry[:violations] += r[:fixed]
        entry[:rules] << r[:rule] if r[:fixed].positive?
        entry[:status] = :dirty if r[:status] != :clean
      end
      # Also count actual files in each module directory.
      Dir.glob(File.join(target, "**", "*")).each do |f|
        next unless File.file?(f)
        rel = f.delete_prefix(@root + "/").split("/")[0..2].join("/")
        by_mod[rel][:path] ||= rel
      end
      by_mod.values
    end

    # Architecture #2: Kahn's algorithm topological sort.
    def topo_sort(rules, deps)
      id_map   = rules.index_by(&:id)
      in_deg   = Hash.new(0)
      adj      = Hash.new { |h, k| h[k] = [] }

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
        adj[id].each do |nxt|
          in_deg[nxt] -= 1
          queue << nxt if in_deg[nxt].zero?
        end
      end
      # Append any rules not in the dep graph (no deps declared).
      sorted + (rules - sorted)
    end

    def load_deps
      data = Master.load_yaml(DEPS_PATH)
      deps_raw = data&.dig("deps") || {}
      deps_raw.transform_values { |v| Array(v["after"] || []) }
    rescue StandardError => _e
      {}
    end

    def collect_files(target)
      Dir.glob(File.join(target, "**", "*"))
         .select { |f| File.file?(f) }
         .reject { |f| SKIP_DIRS.any? { |d| f.include?(d) } }
         .sort
    end

    def commit_if_dirty
      return unless @git&.dirty?(".")
      @git.add_lib_files
      @git.commit(GIT_COMMIT_MSG)
    rescue StandardError => e
      @bus&.publish("super_loop:commit_error", error: e.message)
    end
  end
  end
end
