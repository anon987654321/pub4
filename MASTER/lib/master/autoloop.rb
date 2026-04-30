# frozen_string_literal: true

require "open3" # No longer directly used, moving to Master::GitOperations
require_relative "git_operations"

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
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

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

    def build_fix_prompt(violation, src)
      "Fix this Ruby violation in #{violation[:file]}.\n" \
        "Rule: #{violation[:rule]}\n" \
        "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
        "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
        "```ruby\n#{src}\n```"
    end

    # Reflexion-style prefix: tell the model the prior attempt failed and why.
    # Directly inspired by arxiv:2503.14340 (MANTRA Repair Agent).
    def reflected_prompt(base, last_error, attempt)
      "Prior attempt (#{attempt}) failed with: #{last_error[0, 200]}\n" \
        "Reflect briefly on what went wrong, then retry.\n\n" \
        "#{base}"
    end

    def extract_code(text)
      return text.match(/```ruby\n(.*?)```/m)[1].strip if text.match?(/```ruby\n(.*?)```/m)
      return text.match(/```\n(.*?)```/m)[1].strip if text.match?(/```\n(.*?)```/m)
      return text.strip if text.match?(/frozen_string_literal|module |class /)
      nil
    end

    # Safety guards: size check + syntax check before writing.
    # Rejects any fix that removes more than 20% of the original content.
    def apply_fix(rel_path, content)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)

      original_size = File.size(path)
      if content.bytesize < (original_size * MIN_SIZE_RATIO).to_i # GUARD_EXPENSIVE
        @bus&.publish("autoloop:fix_rejected", file: rel_path,
                      reason: "too short (#{content.bytesize} vs #{original_size})")
        return
      end

      return unless syntax_ok?(content) # GUARD_EXPENSIVE

      File.write(path, content, encoding: "UTF-8")
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    end

    # Returns 0.0-1.0. Signals how structurally complete the LLM output is.
    # Low score triggers escalation retry with a reflective prompt (Task #15).
    def confidence_score(code, original_src)
      return 0.0 if code.nil? || code.strip.empty?

      score = 0.0
      score += SCORE_INCREMENT if code.include?("# frozen_string_literal: true")
      score += SCORE_INCREMENT if code.match?(/\A.*?(?:module |class )[A-Z]/m)
      ratio  = code.bytesize.to_f / [original_src.bytesize, 1].max
      score += SCORE_INCREMENT if ratio >= MIN_SIZE_RATIO && ratio <= MAX_SIZE_RATIO
      score += SCORE_INCREMENT if syntax_ok?(code)
      score
    end

    def syntax_ok?(content)
      require "tempfile"
      Tempfile.open(["al_chk", ".rb"]) do |f|
        f.binmode
        f.write(content.encode("UTF-8", invalid: :replace, undef: :replace))
        f.flush
        system("ruby", "-c", f.path, out: File::NULL, err: File::NULL)
      end
    rescue StandardError # DEGRADE_GRACEFULLY
      false
    end

    def track_recurrence(violations)
      return unless @soul
      tally = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
      tally.each do |rule_id, count|
        @rule_recurrence[rule_id] += 1
        next unless @rule_recurrence[rule_id] >= 3
        @rule_recurrence.delete(rule_id)
        sample = violations.select { |v| v[:rule].to_s == rule_id }.first(5)
        result = @soul.propose_from_violations(rule_id, sample, agent: @agent)
        @bus&.publish("autoloop:soul_proposal", rule: rule_id, result: result.to_s[0, 80])
      end
      # Reset rules that disappeared
      (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
    end
  end
end
