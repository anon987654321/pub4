# frozen_string_literal: true

require "open3" # No longer directly used, moving to Master::GitOperations
require_relative "git_operations"

require_relative "autoloop/fix_evaluator"

module Master
  # AutoLoop — iterate on scan violations until clean or max_cycles reached.
  #
  # Cycle: scan lib+test at standard depth → collect violations by severity →
  # LLM fix (full file, no truncation) → size guard → syntax check → write → commit.
  # Stops when clean or max_cycles reached.
  #
  # Retry strategy is Reflexion-style (MANTRA/RefAgent):
  # on rate-limit or transient failure, the failing prompt plus error summary
  # are fed back in a second attempt. Raw retries alone hit ~45% test-pass
  # in RefAgent; self-reflection lifts it to ~90%.
  #
  # Ref: arxiv:2503.14340 (MANTRA), arxiv:2511.03153 (RefAgent).
  class AutoLoop
    MAX_CYCLES       = 12
    BATCH_SIZE       = 3
    RATE_LIMIT_SLEEP = 15     # ONE_SOURCE: no more hardcoded `sleep 15`.freeze
    MAX_FIX_RETRIES  = 3
    SCORE_INCREMENT  = 0.25
    MAX_SIZE_RATIO   = 2.0
    MIN_SIZE_RATIO       = 0.80   # Reject fix if output < 80% of original file size.freeze
    CONFIDENCE_THRESHOLD = 0.60   # Below this, escalate to a reflective retry.freeze
    MAX_FILE_BYTES   = 16_000 # Raised from 4_000 so core files (agent.rb, cli.rb) are fixable.freeze

    # Rules that cannot be safely auto-fixed by rewriting a single file.
    # duplicate_code requires cross-file refactoring; conceptual/adversarial are LLM-only.
    SKIP_RULES = %w[duplicate_code conceptual adversarial axiom_coverage immutable self_explaining long_method pola srp cqs].freeze

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    # Transient error signatures that trigger a reflected retry
    # rather than abandon the fix. 429 = rate limit, 503 = overload.
    TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil)
      @agent          = agent
      @scanner        = scanner
      @root           = root
      @bus            = event_bus
      @soul           = soul
      @rule_recurrence = Hash.new(0) # rule_id => consecutive_cycle_count
      @git            = GitOperations.new(root)
    end

    def run(max_cycles: MAX_CYCLES)
      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        scan_paths  = %w[lib test].map { |d| File.join(@root, d) }
        all_results = scan_paths.flat_map { |dir|
          res = @scanner.scan_dir(dir, depth: :standard)
          res.ok? ? res.value! : []
        }

        violations = extract_violations(all_results)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        # Deduplicate by file — one fix per unique file to avoid write-race.
        by_file = violations.first(BATCH_SIZE * 2).uniq { |v| v[:file] }.first(BATCH_SIZE)

        mutex   = Mutex.new
        fixes   = {}
        stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE  # 5 s apart — stays within free-tier quota

        threads = by_file.each_with_index.map do |v, idx|
          sleep(stagger * idx) if idx.positive?
          Thread.new do
            fix = request_fix(v)
            mutex.synchronize { fixes[v[:file]] = [v, fix] } if fix
          end
        end
        threads.each(&:join)

        fixes.each_value { |v, fix| apply_fix(v[:file], fix) }

        if @git.dirty?("lib/")
          @git.add_lib_files
          @git.commit("autoloop: fix scan violations [cycle #{cycle}]")
          learnings = Learnings.new(root: @root)
          fixes.each_value do |v, _|
            learnings.record(trigger: v[:rule].to_s, strategy: "autoloop_fix", outcome: "commit")
          end
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    include FixEvaluator
    private

    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.ok?
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .reject { |f| SKIP_RULES.include?(f[:rule].to_s) }
          .map    { |f| f.merge(file: path.delete_prefix("#{@root}/")) }
      }.select { |f|
        full_path = File.join(@root, f[:file])
        File.exist?(full_path) && File.size(full_path) <= MAX_FILE_BYTES # GUARD_EXPENSIVE
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    # Request a fix from the LLM. Sends FULL file — never truncates.
    # Skips files > MAX_FILE_BYTES (LLM output would be truncated, risking corruption).
    # Retries up to MAX_FIX_RETRIES with a reflection step on transient errors.
    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      file_size = File.size(path)
      if file_size > MAX_FILE_BYTES
        @bus&.publish("autoloop:fix_skipped", file: violation[:file],
                      reason: "file too large (#{file_size} bytes)")
        return nil
      end

      src         = File.read(path, encoding: "UTF-8")
      base_prompt = build_fix_prompt(violation, src)
      last_error  = nil

      MAX_FIX_RETRIES.times do |attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        begin
          # On retries, inject the last error as a reflection prefix.
          prompt = attempt.zero? ? base_prompt : reflected_prompt(base_prompt, last_error, attempt)
          fix    = extract_code(@agent.ask(prompt).to_s)
          if fix && confidence_score(fix, src) < CONFIDENCE_THRESHOLD && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:escalate", file: violation[:file], attempt: attempt + 1)
            last_error = 'low confidence'
            next
          end
          return fix
        rescue StandardError => e
          last_error = e.message.to_s
          if TRANSIENT_RE.match?(last_error) && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:rate_limit", sleep: RATE_LIMIT_SLEEP * (attempt + 1), attempt: attempt + 1)
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: last_error[0, 120])
            return nil
          end
        end
      end
      nil
    end
  end
end
