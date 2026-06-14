# frozen_string_literal: true

require "digest"
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
        @conflicts = ConflictResolver.new(root: root, bus: bus)
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
        @bus&.publish("rule_loop:pass", rule: @rule.id, violations: violations.size, fixed: fixed, status: status)
        { fixed: fixed, status: status }
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
          next unless fingerprint_matches?(v)
          note_unverified_fix(v)
          new_src = v[:severity].to_sym == :error ? council_fix(v) : request_fix(v)
          new_src = reflexion_verify(v, new_src) if new_src
          apply(v[:file], new_src, v) && (fixed += 1) if new_src
        end
        fixed
      end

      def reflexion_verify(violation, proposed_src)
        path = violation[:file]
        return proposed_src unless File.exist?(path)

        original_src = File.read(path, encoding: "UTF-8") rescue (return proposed_src)
        prompt = <<~PROMPT
          Verify this proposed code fix is correct. Reply ONLY with "SAFE" or "UNSAFE: <reason>".

          VIOLATION: #{violation[:rule]} line #{violation[:line]} — #{violation[:message]}

          ORIGINAL:
          ```
          #{original_src[0, 600]}
          ```

          PROPOSED FIX:
          ```
          #{proposed_src[0, 600]}
          ```
        PROMPT
        response = @agent.ask_once(prompt).to_s.strip
        if response.start_with?("UNSAFE")
          @bus&.publish("rule_loop:reflexion_rejected", rule: @rule.id, file: path, reason: response[0, 160])
          return nil
        end
        @bus&.publish("rule_loop:reflexion_approved", rule: @rule.id, file: path)
        proposed_src
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLoop.reflexion_verify", rule: @rule.id)
        proposed_src
      end

      # Architecture #6: three-reviewer veto for error-tier violations.
      def council_fix(violation)
        path = violation[:file]
        return unless File.exist?(path)
        src    = File.read(path, encoding: "UTF-8")
        prompt = build_prompt_for(violation: violation, src: src, path: path, style: :council)
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
        if src.lines.count > 200
          architect_then_fix(violation: violation, src: src, path: path)
        else
          src.bytesize > PatchApplier::DIFF_THRESHOLD ? diff_fix(violation: violation, src: src, path: path) : genetic_fix(violation: violation, src: src, path: path)
        end
      end

      # Architecture #5: unified diff patch — safe on large files.
      def diff_fix(violation:, src:, path:)
        prompt = build_prompt_for(violation: violation, src: src, path: path, style: :diff)
        MAX_FIX_RETRIES.times do |attempt|
          wait_before_retry(attempt, rule: @rule.id, file: path, mode: :diff)
          response = @agent.ask(prompt).to_s
          next if response.strip == "UNCHANGED"
          result = PatchApplier.apply(src, response)
          return result.source if result.is_a?(PatchApplier::Success)
          return whole_file_fallback(violation: violation, src: src, path: path, reason: result.reason)
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
        prompt = build_prompt_for(violation: violation, src: src, path: path)
        candidates = fix_attempt(violation, attempts: genetic_autofix_candidates, event: "rule_loop:fix_error").codes(
          prompt: prompt,
          ext: ext,
          source: src,
          wait_context: { rule: @rule.id, file: path, mode: :genetic }
        )
        best_candidate(candidates || [], path)
      end

      def architect_then_fix(violation:, src:, path:)
        strong_model = routing_model_ids[:strong]
        fast_model = routing_model_ids[:fast]
        plan = architecture_plan(violation: violation, src: src, path: path, model: strong_model)
        return whole_file_fallback(violation: violation, src: src, path: path, reason: "no architecture plan") if plan.to_s.strip.empty?

        prompt = build_prompt_for(
          violation: violation,
          src: src,
          path: path,
          style: :file
        ) + "\n\nArchitecture plan:\n#{plan}"
        response = fast_model ? @agent.ask_once(prompt, model: fast_model) : @agent.ask_once(prompt)
        response = extract_code(response.to_s, File.extname(path).downcase)
        return whole_file_fallback(violation: violation, src: src, path: path, reason: "no code returned") if response.to_s.strip.empty?

        response
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLoop.architect_then_fix", rule: @rule.id)
        whole_file_fallback(violation: violation, src: src, path: path, reason: e.message)
      end

      def fix_attempt(violation, attempts: MAX_FIX_RETRIES, event:)
        FixAttempt.new(
          agent: @agent,
          attempts: attempts,
          wait: ->(attempt, context) { wait_before_retry(attempt, **context) },
          extractor: ->(response, ext) { extract_code(response, ext) },
          on_error: ->(error) { handle_fix_exception(error, violation, event: event) }
        )
      end

      def wait_before_retry(attempt, rule:, file:, mode:)
        return unless attempt.positive?

        delay = RATE_LIMIT_SLEEP * attempt
        @bus&.publish("rule_loop:retry_wait", rule: rule, file: file, mode: mode, attempt: attempt, delay: delay)
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
        if after.size > before.size
          write_atomic(path, old_src, encoding: "UTF-8")
          @bus&.publish("rule_loop:fix_rejected", rule: @rule.id, file: path, reason: "new_violations", before: before.size, after: after.size)
          return false
        end
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
        @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], confidence: confidence) unless allowed
        allowed
      end

      def fingerprint_matches?(violation)
        stored = violation[:fingerprint] || violation["fingerprint"]
        return true if stored.to_s.empty?
        return false unless File.file?(violation[:file].to_s)

        current = semantic_fingerprint_for(violation[:file].to_s)
        if current != stored.to_s
          @bus&.publish("rule_loop:stale_scan", rule: @rule.id, file: violation[:file], expected: stored, actual: current)
          return false
        end
        true
      end

      def whole_file_fallback(violation:, src:, path:, reason:)
        @bus&.publish("rule_loop:edit_format_fallback", rule: @rule.id, file: path, reason: reason.to_s[0, 160])
        prompt = build_prompt_for(violation: violation, src: src, path: path, style: :file)
        model = routing_model_ids[:fast]
        model ? @agent.ask_once(prompt, model: model).to_s : @agent.ask_once(prompt).to_s
      end

      def architecture_plan(violation:, src:, path:, model:)
        prompt = <<~PROMPT
        You are planning a safe refactor for a Ruby file.

        File: #{path}
        Rule: #{violation[:rule]}
        Violation: line #{violation[:line]} — #{violation[:message]}

        Before answering, perform a depth check:
        - enumerate the module hierarchy, data flow, side effects, implicit invariants, and edge cases
        - list direct callers, callees, and related files
        - state the design pattern being used or violated
        - audit assumptions about input types, object state, concurrency, and failure modes
        - run an inversion test: if this plan is wrong, what breaks, where, and when?

        Produce a short architecture plan only:
        1. Identify the smallest missing abstraction or boundary.
        2. List the changes in order.
        3. Name the risks and tests to preserve.

        Source:
        ```ruby
        #{src}
        ```
      PROMPT
        raw = model ? @agent.ask_once(prompt, model: model) : @agent.ask_once(prompt)
        raw.to_s
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLoop.architecture_plan", rule: @rule.id)
        ""
      end

      def routing_model_ids
        @routing_model_ids ||= begin
          models = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml")) || {}
          tiers = models.fetch("models", {})
          {
            strong: first_model_id(tiers["strong"]),
            fast: first_model_id(tiers["fast"] || tiers["cheap"] || tiers["default"])
          }
        rescue StandardError
          { strong: nil, fast: nil }
        end
      end

      def first_model_id(models)
        Array(models).first && Array(models).first["id"]
      end

      def note_unverified_fix(violation)
        return if test_file_for(violation[:file]).any?

          @bus&.publish("rule_loop:fix_unverified", rule: @rule.id, file: violation[:file], note: "fix unverified — add test")
      rescue StandardError
        nil
      end

      def semantic_fingerprint_for(path)
        src = File.read(path, encoding: "UTF-8")
        counts = {
          line_count: src.lines.count,
          class_count: src.scan(/^\s*class\s+/).size,
          method_count: src.scan(/^\s*def\s+/).size,
          def_names: src.scan(/^\s*def\s+([a-zA-Z_][\w!?=]*)/).flatten.sort,
          constant_names: src.scan(/\b([A-Z][A-Z0-9_]*(?:::[A-Z][A-Z0-9_]*)*)\b/).flatten.sort
        }
        Digest::SHA256.hexdigest(Marshal.dump(counts))
      rescue StandardError
        ""
      end

      def test_file_for(path)
        rel = path.to_s.delete_prefix("#{@root}/")
        stem = File.basename(rel, File.extname(rel))
        patterns = [
          File.join(@root, "test", "**", "*#{stem}*.rb"),
          File.join(@root, "MASTER", "test", "**", "*#{stem}*.rb")
        ]
        patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.select { |file| File.file?(file) }
      rescue StandardError
        []
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

        Before answering, do a semantic pass:
        - summarize what the file does in 3 lines
        - summarize what it assumes and what could break
        - enumerate module hierarchy, data flow, side effects, and implicit invariants
        - list direct callers/callees and related files
        - name the design pattern used or violated
        - audit assumptions about nil/empty/max/unicode/concurrency/network/file-permission inputs
        - state the inversion test: if this fix is wrong, what breaks, where, and when?

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
        @learnings.record(rule: @rule.id, file_type: ext, outcome: outcome)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.record_outcomes", event_bus: @bus, rule: @rule.id)
      end
    end
  end
end
