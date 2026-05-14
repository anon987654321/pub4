# frozen_string_literal: true

require "open3"
require_relative "../reach/git_operations"

require_relative "auto_loop/fix_evaluator"

module Master
  module Loop
  class AutoLoop
    def self.load_cfg
      Master.load_yaml(File.join(Master::ROOT, "data", "workflow.yml"))
            .dig("autoloop") || {}
    rescue StandardError => _e
      {}
    end

    _cfg = load_cfg
    MAX_CYCLES           = _cfg.fetch("max_cycles",           12)
    BATCH_SIZE           = _cfg.fetch("batch_size",            3)
    RATE_LIMIT_SLEEP     = _cfg.fetch("rate_limit_sleep",     15)
    MAX_FIX_RETRIES      = _cfg.fetch("max_fix_retries",       3)
    CONFIDENCE_THRESHOLD = _cfg.fetch("confidence_threshold", 0.60)
    MAX_FILE_BYTES       = _cfg.fetch("max_file_bytes",   16_000)
    SKIP_RULES           = Array(_cfg.fetch("skip_rules", [])).freeze
    TARGETS              = Array(_cfg.fetch("targets", %w[lib/ test/ data/ web/ DEPLOY/])).freeze
    EXCLUDES             = Array(_cfg.fetch("excludes", %w[vendor/ knowledge/])).freeze

    SCORE_INCREMENT = 0.25
    MAX_SIZE_RATIO  = 2.0
    MIN_SIZE_RATIO  = 0.80

    SEVERITY_RANK = Master::SEVERITY_RANK
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil, learnings: nil)
      @agent           = agent
      @scanner         = scanner
      @root            = root
      @bus             = event_bus
      @soul            = soul
      @learnings       = learnings
      @rule_recurrence = Hash.new(0) # rule_id => consecutive_cycle_count
      @git             = Reach::GitOperations.new(root)
    end

    def run(max_cycles: MAX_CYCLES)
      saved_model = @agent.model
      @agent.model = @agent.model_for(operation: :autoloop)
      consecutive_clean = 0
      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        scan_paths  = TARGETS.map { |d| File.join(@root, d.delete_suffix("/")) }
                              .select { |d| File.directory?(d) }
        all_results = scan_paths.flat_map { |dir|
          scan_result = @scanner.scan_dir(dir, depth: :deep)
          scan_result.ok? ? scan_result.value! : []
        }

        violations = extract_violations(all_results)
        if violations.empty?
          consecutive_clean += 1
          return Result.ok("clean after #{cycle} cycle(s) (fixed-point: 2 silent runs)") if consecutive_clean >= 2
          @bus&.publish("autoloop:provisional_clean", cycle:, consecutive_clean:)
          next
        end
        consecutive_clean = 0

        yield cycle, violations if block_given?

        # Deduplicate by file — one fix per unique file to avoid write-race.
        by_file = violations.first(BATCH_SIZE * 2).uniq { |v| v[:file] }.first(BATCH_SIZE)

        mutex   = Mutex.new
        fixes   = {}
        stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE  # 5 s apart — stays within free-tier quota

        threads = by_file.each_with_index.map do |v, idx|
          Thread.new do
            sleep(stagger * idx) if idx.positive?
            fix = request_fix(v)
            mutex.synchronize { fixes[v[:file]] = [v, fix] } if fix
          rescue StandardError => e
            @bus&.publish("autoloop:thread_error", file: v[:file], error: e.message)
          end
        end
        threads.each(&:join)

        fixes.each_value { |v, fix| apply_fix(v[:file], fix) }

        if @git.dirty?("lib/")
          @git.add_lib_files
          @git.commit("autoloop: fix scan violations [cycle #{cycle}]")
          if @learnings
            fixes.each_value { |v, _|
 @learnings.record(trigger: v[:rule].to_s, strategy: "autoloop_fix", outcome: "commit") }
          end
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    ensure
      @agent.model = saved_model if defined?(saved_model) && saved_model
    end

    include FixEvaluator
    private

    def apply_fix(rel_path, fixed_src)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)
      original = File.read(path, encoding: "UTF-8")
      return if fixed_src.strip == original.strip
      temporary_path = "#{path}.tmp.#{Process.pid}"
      File.write(temporary_path, fixed_src)
      File.rename(temporary_path, path)
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    rescue StandardError => e
      @bus&.publish("autoloop:write_error", file: rel_path, error: e.message)
    end

    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.ok?
        rel = path.delete_prefix("#{@root}/")
        next [] if EXCLUDES.any? { |ex| rel.start_with?(ex) }
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .reject { |f| SKIP_RULES.include?(f[:rule].to_s) }
          .map    { |f| f.merge(file: rel) }
      }.select { |f|
        full_path = File.join(@root, f[:file])
        File.exist?(full_path) && File.size(full_path) <= MAX_FILE_BYTES # GUARD_EXPENSIVE
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return unless File.exist?(path)

      file_size = File.size(path)
      if file_size > MAX_FILE_BYTES
        @bus&.publish("autoloop:fix_skipped", file: violation[:file],
                      reason: "file too large (#{file_size} bytes)")
        return
      end

      src         = File.read(path, encoding: "UTF-8")
      base_prompt = build_fix_prompt(violation, src)
      result = Judge::Reflexion.run(agent: @agent, task: base_prompt, max: MAX_FIX_RETRIES) do |prompt, attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        begin
          fix = extract_code(@agent.ask(prompt).to_s)
          next nil if fix.nil?
          next nil if confidence_score(fix, src) < CONFIDENCE_THRESHOLD
          fix
        rescue StandardError => e
          err = e.message.to_s
          if TRANSIENT_RE.match?(err) && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:rate_limit", sleep: RATE_LIMIT_SLEEP * (attempt + 1), attempt: attempt + 1)
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: err[0, 120])
          end
          nil
        end
      end
      Result.wrap(result).value_or(nil)
    end
  end
  end
end
