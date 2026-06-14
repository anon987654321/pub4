# frozen_string_literal: true

require "tempfile"
require_relative "../ground/atomic_write"
require_relative "conflict_resolver"
require_relative "constants"
require_relative "fix_attempt"
require_relative "fix_helpers"
require_relative "patch_applier"
require_relative "severity"
require_relative "violation"

module Master
  module Loop
  # Single-pass fixer for one rule across a set of files.
  # FixLoop owns the outer convergence loop; RuleLoop fixes one batch per call.
  #
  # Fix routing (per violation severity + file size):
  #   error tier  → council_fix   (3-reviewer veto before apply)
  #   large file  → diff_fix      (unified diff patch; arch #5)
  #   small file  → genetic_fix   (N candidates, rescan, best wins; arch #9)
    class RuleLoop
      RATE_LIMIT_SLEEP = 10
      MAX_FIX_RETRIES = 2
      RETRY_WAIT_SLICE = 0.25
      GENETIC_AUTOFIX_CANDIDATES = 3

      MIN_SEVERITY = :warning
      @soul_preamble_mutex = Mutex.new
      @soul_preamble_cache = nil

      class << self
        def clear_preamble_cache!
          @soul_preamble_mutex.synchronize { @soul_preamble_cache = nil }
        end

        def soul_preamble
          @soul_preamble_mutex.synchronize do
            @soul_preamble_cache ||= build_soul_preamble
          end
        end

        private

        def build_soul_preamble
          soul   = Master.load_yaml(Master.data_path("soul.yml"))
          abs    = soul.fetch("absolute", {})
          golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          lines  = ["Golden rule: #{golden}",
                    "Minimum change that eliminates the violation. Do not touch unrelated code."]
          abs.fetch("code_rules", {}).each { |key, value| lines << "- #{key}: #{value}" }
          abs.fetch("aesthetic_rules", {}).each { |key, value| lines << "- #{key}: #{value}" }
          lines.join("\n")
        rescue StandardError
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end

      include Master::Ground::AtomicWrite
      include Master::Loop::FixHelpers

      def initialize(rule:, agent:, scanner:, root:, bus: nil, learnings: nil)
        @rule = rule
        @agent = agent
        @scanner = scanner
        @root = root
        @bus = bus
        @learnings = learnings
        @conflicts = ConflictResolver.new(root:, bus:)
      end

      def injected_preamble=(text)
        @injected_preamble = text
      end

      # One pass: scan → fix each violating file once → return { fixed:, status: }.
      def run_once(files)
        violations = scan_files(files)
        return { fixed: 0, status: :clean } if violations.empty?

        fixed = fix_batch(violations)
        status = fixed > 0 ? :fixed : :stuck
        record_outcomes(files, fixed > 0 ? :fixed : :stuck)
        @bus&.publish("rule_loop:pass", rule: @rule.id, violations: violations.size, fixed:, status:)
        { fixed:, status: }
      rescue StandardError => e
        @bus&.publish("rule_loop:error", rule: @rule.id, error: e.message)
        { fixed: 0, status: :error }
      end

      private

      def convergence_cfg
        @convergence_cfg ||= Master.load_yaml(Master::RULES_PATH).dig("thresholds", "convergence") || {}
      rescue StandardError
        {}
      end

      def genetic_autofix_candidates
        convergence_cfg["genetic_autofix_candidates"] || GENETIC_AUTOFIX_CANDIDATES
      end

      def scan_files(files)
        files.flat_map do |path|
          next [] unless File.exist?(path)
          result = @scanner.scan(path, rules: [@rule])
          next [] unless result.ok?
          ext = File.extname(path).downcase
          result.value!
                .select { |f| Severity.at_least?(f[:severity], MIN_SEVERITY) }
                .map    { |f| Violation.from_finding(f, file: path, ext: ext) }
        end
      end

      def fix_batch(violations)
        fixed = 0
        violations.uniq { |v| v[:file] }.each do |v|
          next unless autofix_allowed?(v)
          new_src = v[:severity].to_sym == :error ? council_fix(v) : request_fix(v)
          apply(v[:file], new_src, v) && (fixed += 1) if new_src
        end
        fixed
      end

      # Architecture #6: three-reviewer veto for error-tier violations.
      def council_fix(violation)
        path = violation[:file]
        return unless File.exist?(path)
        src    = File.read(path, encoding: "UTF-8")
        prompt = build_prompt_for(violation:, src:, path:, style: :council)
        fix_attempt(violation, event: "rule_loop:council_error").first_code(
          prompt: prompt,
          ext: File.extname(path).downcase,
          source: src,
          wait_context: { rule: @rule.id, file: path, mode: :council }
        )
      end

      # Architecture #5 + #9: diff for large files, genetic candidates for small.
      def request_fix(violation)
        path = violation[:file]
        return unless File.exist?(path)
        src = File.read(path, encoding: "UTF-8")
        src.bytesize > PatchApplier::DIFF_THRESHOLD ? diff_fix(violation:, src:, path:) : genetic_fix(violation:, src:, path:)
      end

      # Architecture #5: unified diff patch — safe on large files.
      def diff_fix(violation:, src:, path:)
        prompt = build_prompt_for(violation:, src:, path:, style: :diff)
        MAX_FIX_RETRIES.times do |attempt|
          wait_before_retry(attempt, rule: @rule.id, file: path, mode: :diff)
          response = @agent.ask(prompt).to_s
          next if response.strip == "UNCHANGED"
          result = PatchApplier.apply(src, response)
          return result.source if result.is_a?(PatchApplier::Success)
        rescue StandardError => e
          action = handle_fix_exception(e, violation, event: "rule_loop:fix_error")
          next if action == :retry
          return nil
        end
        nil
      end

      # Architecture #9: generate candidates, rescan each, apply lowest-violation winner.
      def genetic_fix(violation:, src:, path:)
        ext    = File.extname(path).downcase
        prompt = build_prompt_for(violation:, src:, path:)
        candidates = fix_attempt(violation, attempts: genetic_autofix_candidates, event: "rule_loop:fix_error").codes(
          prompt: prompt,
          ext: ext,
          source: src,
          wait_context: { rule: @rule.id, file: path, mode: :genetic }
        )
        best_candidate(candidates || [], path)
      end

      def fix_attempt(violation, attempts: MAX_FIX_RETRIES, event:)
        FixAttempt.new(
          agent: @agent,
          attempts: attempts,
          wait: ->(attempt, context) { wait_before_retry(attempt, **context) },
          extractor: ->(response, ext) { extract_code(response, ext) },
          on_error: ->(error) { handle_fix_exception(error, violation, event:) }
        )
      end

      def wait_before_retry(attempt, rule:, file:, mode:)
        return unless attempt.positive?

        delay = RATE_LIMIT_SLEEP * attempt
        @bus&.publish("rule_loop:retry_wait", rule:, file:, mode:, attempt:, delay:)
        deadline = Time.now + delay
        while (remaining = deadline - Time.now).positive?
          sleep [remaining, RETRY_WAIT_SLICE].min
          Thread.pass
        end
      end

      def best_candidate(candidates, path)
        return nil if candidates.empty?
        return candidates.first if candidates.size == 1
        orig = File.read(path, encoding: "utf-8") rescue nil
        baseline = orig ? (rescan_candidate(orig, path) rescue nil) : nil
        scored = candidates.filter_map do |c|
          count = rescan_candidate(c, path)
          [count, c] unless baseline && count > baseline
        end
        scored.empty? ? nil : scored.min_by(&:first).last
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLoop.best_candidate", rule: @rule.id)
        candidates.first
      end

      def rescan_candidate(candidate, path)
        Tempfile.open(["rl_score", File.extname(path)]) do |f|
          f.write(candidate); f.flush
          result = @scanner.scan(f.path, rules: [@rule])
          result.ok? ? result.value!.size : 99
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLoop.rescan_candidate", rule: @rule.id)
        99
      end

      def apply(path, new_src, violation)
        old_src = File.read(path, encoding: "UTF-8")
        before = scan_all(path)
        write_atomic(path, new_src, encoding: "UTF-8")
        after = scan_all(path)
        if @conflicts.reject_higher_priority?(original_violation: violation, before: before, after: after, path: path)
          write_atomic(path, old_src, encoding: "UTF-8")
          @bus&.publish("rule_loop:fix_rejected", rule: @rule.id, file: path, reason: "higher_priority_violation")
          return false
        end
        @bus&.publish("rule_loop:fix_applied", rule: @rule.id, file: path)
        true
      rescue StandardError => e
        @bus&.publish("rule_loop:write_error", rule: @rule.id, file: path, error: e.message)
        false
      end

      def scan_all(path)
        result = @scanner.scan(path)
        result.ok? ? result.value! : []
      rescue StandardError
        []
      end

      def autofix_allowed?(violation)
        return true unless @scanner.respond_to?(:should_autofix?, true)

        confidence = violation[:confidence] || violation["confidence"] || 1.0
        allowed = @scanner.__send__(:should_autofix?, violation[:rule], confidence)
        @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], confidence:) unless allowed
        allowed
      end

      def handle_fix_exception(error, violation, event:)
        message = error.message.to_s
        if Master::Loop::Constants::TRANSIENT_RE.match?(message)
          return :retry
        elsif Master::Loop::Constants::PERMANENT_RE.match?(message)
          @bus&.publish("rule_loop:fail_fast", rule: violation[:rule], file: violation[:file], error: message[0, 120])
        elsif Master::Loop::Constants::AMBIGUOUS_RE.match?(message)
          @bus&.publish("rule_loop:human_intervention", rule: violation[:rule], file: violation[:file], error: message[0, 120])
        else
          @bus&.publish(event, rule: violation[:rule], file: violation[:file], error: message[0, 120])
        end
        :stop
      end

      def build_prompt_for(violation:, src:, path:, style: :file)
        lang     = Master::Judge::Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
        fix_hint = violation[:fix].to_s.strip
        fix_line = fix_hint.empty? ? "" : "How to fix: #{fix_hint}"
        action = prompt_action(style)
        <<~PROMPT
        #{preamble}

        File: #{File.basename(path)} (#{lang})
        Rule violated: #{violation[:rule]}
        Line #{violation[:line]}: #{violation[:message]}
        #{fix_line}

        #{action}

        ```#{lang}
        #{src}
        ```
      PROMPT
      end

      def prompt_action(style)
        case style
        when :council
          <<~TEXT.chomp
          Three reviewers assess before any fix is applied:
          As Skeptic: Is this a real violation or a false positive? What is the blast radius?
          As Security: Does this create an attack surface? What must the fix preserve?
          As Maintainer: What is the minimum change that eliminates the violation without drift?

          Produce the corrected file only if all three agree the fix is safe.
          If any reviewer would block, return exactly: UNCHANGED
          TEXT
        when :diff
          "Return a unified diff patch only (like `diff -u`). Fix only the violation.\nIf unsafe to autofix, return exactly: UNCHANGED"
        else
          "Return ONLY the corrected file. If unsafe to autofix, return exactly: UNCHANGED"
        end
      end

      def preamble
        @injected_preamble || self.class.soul_preamble
      end

      # Architecture #10: record fix quality in learnings store.
      def record_outcomes(files, outcome)
        return unless @learnings
        ext = files.filter_map { |f| File.extname(f).downcase.delete(".").presence }.tally.max_by { |_, n| n }&.first || "unknown"
        @learnings.record(rule: @rule.id, file_type: ext, outcome:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.record_outcomes", event_bus: @bus, rule: @rule.id)
      end
    end
  end
end
