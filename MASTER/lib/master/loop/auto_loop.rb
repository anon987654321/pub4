# frozen_string_literal: true

require "open3"
require "tempfile"
require_relative "../reach/git_operations"
require_relative "../reach/atomic_write"
require_relative "constants"
require_relative "fix_helpers"

module Master
  module Loop
  class AutoLoop
    module FixEvaluator
      ERROR_TRUNCATE = 200
      private

      def build_fix_prompt(violation, src)
        "#{constitutional_preamble}\n\n" \
          "Fix this Ruby violation in #{violation[:file]}.\n" \
          "Rule: #{violation[:rule]}\n" \
          "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
          "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
          "```ruby\n#{src}\n```"
      end

      def axioms=(text) = @injected_axioms = text

      def constitutional_preamble
        @constitutional_preamble ||= @injected_axioms || begin
          soul  = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
          rules = Master.load_yaml(File.join(Master::ROOT, "data", "rules.yml"))
          abs    = soul.fetch("absolute", {})
          golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          zen    = rules.fetch("zen", {})
          lines  = ["Constitutional constraints:", "- Golden rule: #{golden}"]
          zen.each_value { |v| lines << "- #{v}" } if zen.is_a?(Hash)
          abs.fetch("code_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
          abs.fetch("aesthetic_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
          lines.join("\n")
        rescue StandardError => _e
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end

      def reflected_prompt(base, last_error, attempt)
        "Prior attempt (#{attempt}) failed with: #{last_error[0, ERROR_TRUNCATE]}\n" \
          "Reflect briefly on what went wrong, then revise.\n\n#{base}"
      end

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
        Tempfile.open(["al_chk", ".rb"]) do |f|
          f.binmode
          f.write(content.encode("UTF-8", invalid: :replace, undef: :replace))
          f.flush
          system("ruby", "-c", f.path, out: File::NULL, err: File::NULL)
        end
      rescue StandardError => _e
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
          @bus&.publish("autoloop:soul_proposal", rule: rule_id, sample: sample)
          @bus&.publish("autoloop:soul_proposal", rule: rule_id, result: "queued")
          append_improvement(rule_id, sample)
        end
        (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
      end

      def append_improvement(rule_id, sample)
        path = File.join(@root, "runtime", "improvements.md")
        FileUtils.mkdir_p(File.dirname(path))
        files = sample.map { |v| v[:file] }.uniq.first(3).join(", ")
        entry = "#{Time.now.utc.strftime("%Y-%m-%d %H:%M")} #{rule_id}: recurring in #{files}\n"
        File.open(path, "a") { |f| f.write(entry) }
      rescue StandardError => _e
        nil
      end
    end
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

    include Master::Reach::AtomicWrite
    include Master::Loop::FixHelpers
    include FixEvaluator

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil, learnings: nil)
      @agent           = agent
      @scanner         = scanner
      @root            = root
      @bus             = event_bus
      @soul            = soul
      @learnings       = learnings
      # rule_id → consecutive cycle count
      @rule_recurrence = Hash.new(0)
      @git             = Reach::GitOperations.new(root)
    end

    def run(max_cycles: MAX_CYCLES)
      @agent.with_model(@agent.model_for(operation: :autoloop)) do
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
          # Stagger requests 5 s apart — stays within free-tier quota.
          stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE

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
      end
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    private

    def apply_fix(rel_path, fixed_src)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)
      original = File.read(path, encoding: "UTF-8")
      return if fixed_src.strip == original.strip
      write_atomic(path, fixed_src)
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
        # GUARD_EXPENSIVE: skip files too large to process safely.
        File.exist?(full_path) && File.size(full_path) <= MAX_FILE_BYTES
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
          fix = extract_code(@agent.ask(prompt).to_s, ".rb")
          next nil if fix.nil?
          next nil if confidence_score(fix, src) < CONFIDENCE_THRESHOLD
          fix
        rescue StandardError => e
          err = e.message.to_s
          if Master::Loop::Constants::TRANSIENT_RE.match?(err) && attempt < MAX_FIX_RETRIES - 1
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
