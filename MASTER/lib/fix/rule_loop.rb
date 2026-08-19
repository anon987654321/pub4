# frozen_string_literal: true

require "digest"
require "tempfile"
require_relative "../ground/atomic_write"
require_relative "conflict_resolver"
require_relative "constants"
require_relative "fix_attempt"
require_relative "patch_applier"
require_relative "severity"
require_relative "violation"
require_relative "rule_loop/fix_strategies"
require_relative "rule_loop/fix_verification"
require_relative "rule_loop/outcome_tracking"

module Master
  module Fix
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
      CONVERGE_THRESHOLD = 0.05

      MIN_SEVERITY = :warning

      SEMANTIC_PASS_CHECKLIST = <<~TEXT.strip
        Before answering, do a semantic pass:
        - summarize what the file does in 3 lines
        - summarize what it assumes and what can break
        - enumerate module hierarchy, data flow, side effects, and implicit invariants
        - list direct callers/callees and related files
        - name the design pattern used or violated
        - audit assumptions about nil/empty/max/unicode/concurrency/network/file-permission inputs
        - state the inversion test: if this fix is wrong, what breaks, where, and when?
      TEXT

      @soul_preamble_mutex = Mutex.new
      @soul_preamble_cache = nil

      class << self
        def clear_preamble_cache!
          @soul_preamble_mutex.synchronize do
            @soul_preamble_cache = nil
            @soul_preamble_mtime = nil
          end
        end

        def soul_preamble
          @soul_preamble_mutex.synchronize do
            path = Master.data_path("soul.yml")
            mtime = File.mtime(path).to_i
            return @soul_preamble_cache if @soul_preamble_cache && @soul_preamble_mtime == mtime

            @soul_preamble_mtime = mtime
            @soul_preamble_cache = build_soul_preamble
          end
        end

        private

        def build_soul_preamble
          soul   = Master.load_yaml(Master.data_path("soul.yml"))
          abs    = soul.fetch("absolute", {})
          golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          lines  = ["Golden rule: #{golden}",
                    "Minimum change that eliminates the violation. Do not touch unrelated code."]
          abs.fetch("rules", {}).each { |key, value| lines << "- #{key}: #{value}" }
          abs.fetch("aesthetic_rules", {}).each { |key, value| lines << "- #{key}: #{value}" }
          lines.join("\n")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "rule_loop.golden_rule")
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end

      include Master::Ground::AtomicWrite
      include FixStrategies
      include FixVerification
      include OutcomeTracking

      def initialize(rule:, agent:, scanner:, root:, **options)
        @rule = rule
        @agent = agent
        @scanner = scanner
        @root = root
        @bus = options[:bus]
        @learnings = options[:learnings]
        @conflicts = ConflictResolver.new(root:, bus: @bus)
      end

      def injected_preamble=(text)
        @injected_preamble = text
      end

      # One pass: scan → fix each violating file once → return { fixed:, status: }.
      def run_once(files)
        violations = scan_files(files)
        return { fixed: 0, status: :clean } if violations.empty?

        fixed = fix_batch(violations)
        status = pass_outcome(fixed)
        record_outcomes(files, status)
        @bus&.publish("rule_loop:pass", rule: @rule.id, violations: violations.size, fixed:, status:)
        { fixed:, status: }
      rescue StandardError => e
        @bus&.publish("rule_loop:error", rule: @rule.id, error: e.message)
        # Bus-only meant a crashed rule pass was indistinguishable from a
        # quiet one in the dmesg stream the operator actually reads.
        Master::Trace::Dmesg.status("fix0", "rule_error rule=#{@rule.id} #{e.class}: #{e.message[0, 90]}")
        { fixed: 0, status: :error }
      end

      private

      def scan_files(files)
        files.flat_map do |path|
          next [] unless File.exist?(path)
          result = @scanner.scan(path, rules: [@rule])
          next [] unless result.ok?
          ext = File.extname(path).downcase
          result.value!
                .select { |f| Severity.at_least?(f[:severity], MIN_SEVERITY) }
                .map    { |f| Violation.from_finding(f, file: path, ext:) }
        end
      end

      # Returns one outcome symbol per violation, never a bare boolean: the
      # 2026-08-19 proof run reported `fixed=0` for 33 minutes with nothing in
      # the log saying whether proposals never arrived, died in reflexion, or
      # were rejected on re-scan — every non-apply collapsed to `false` before
      # the one line anyone reads. The tally of these symbols is that line.
      def fix_violation(violation)
        return :skip_confidence unless autofix_allowed?(violation)
        return :skip_fingerprint unless fingerprint_matches?(violation)

        note_unverified_fix(violation)
        source = violation[:severity].to_sym == :error ? council_fix(violation) : request_fix(violation)
        return :no_proposal if source.to_s.strip.empty?

        verified = reflexion_verify(violation, source)
        return :reflexion_rejected unless verified

        apply(violation[:file], verified, violation) ? :applied : :rejected
      end

      def apply(path, new_src, violation)
        old_src = File.read(path, encoding: "UTF-8")
        before = scan_all(path)
        write_atomic(path, new_src, encoding: "UTF-8")
        after = scan_all(path)
        return reject_fix(path, old_src, "new_violations", before:, after:) if after.size > before.size
        if @conflicts.reject_higher_priority?(original_violation: violation, before:, after:, path:)
          return reject_fix(path, old_src, "higher_priority_violation")
        end

        @bus&.publish("rule_loop:fix_applied", rule: @rule.id, file: path)
        true
      rescue StandardError => e
        @bus&.publish("rule_loop:write_error", rule: @rule.id, file: path, error: e.message)
        false
      end

      def reject_fix(path, original, reason, **details)
        write_atomic(path, original, encoding: "UTF-8")
        @bus&.publish("rule_loop:fix_rejected", rule: @rule.id, file: path, reason:, **details)
        Master::Trace::Dmesg.status("fix0", "fix_rejected rule=#{@rule.id} file=#{File.basename(path)} reason=#{reason}")
        false
      end

      def build_prompt_for(violation:, src:, path:, style: :file)
        ctx = prompt_context_for(violation:, path:, style:)
        <<~PROMPT
        #{preamble}

        File: #{File.basename(path)} (#{ctx[:lang]})
        Rule violated: #{violation[:rule]}
        Line #{violation[:line]}: #{violation[:message]}
        #{ctx[:fix_line]}

        #{SEMANTIC_PASS_CHECKLIST}

        #{ctx[:action]}

        ```#{ctx[:lang]}
        #{src}
        ```
      PROMPT
      end

      def prompt_context_for(violation:, path:, style:)
        lang = Master::Review::Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
        fix_hint = violation[:fix].to_s.strip
        fix_line = fix_hint.empty? ? "" : "How to fix: #{fix_hint}"
        { lang:, fix_line:, action: prompt_action(style) }
      end

      def prompt_action(style)
        case style
        when :council
          <<~TEXT.chomp
          Three reviewers assess before we apply any fix:
          As Skeptic: Is this a real violation or a false positive? What is the blast radius?
          As Security: Does this create an attack surface? What must the fix preserve?
          As Maintainer: What is the minimum change that eliminates the violation without drift?

          Produce the corrected file only if all three agree the fix is safe.
          If any reviewer blocks, return exactly: UNCHANGED
          TEXT
        when :diff
          "Return a unified diff patch only (like `diff -u`). Fix only the violation.\n" \
            "If unsafe to autofix, return exactly: UNCHANGED"
        else
          "Return ONLY the corrected file. If unsafe to autofix, return exactly: UNCHANGED"
        end
      end

      def preamble
        @injected_preamble || self.class.soul_preamble
      end

      def extract_code(text, ext = nil)
        return if text.nil? || text.strip.empty? || text.strip == "UNCHANGED"

        lang = ext ? ext_language(ext) : "text"
        langs_re = Regexp.union(lang, "text", "")
        match = text.match(/```(?:#{langs_re})?\n(.*?)```/m)
        return match[1].strip if match

        text.strip
      end

      def converged?(prev, current, threshold: CONVERGE_THRESHOLD)
        return false unless prev

        prev == current || (prev.length - current.length).abs < (prev.length * threshold)
      end

      def ext_language(ext)
        Master::Review::Scan::Rule::EXT_LANG.fetch(ext.downcase, "text")
      rescue StandardError
        "text"
      end

      def convergence_cfg
        @convergence_cfg ||= Master.load_yaml(Master::RULES_PATH).dig("thresholds", "convergence") || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.convergence_cfg", event_bus: @bus)
        {}
      end

      def genetic_autofix_candidates
        convergence_cfg["genetic_autofix_candidates"] || RuleLoop::GENETIC_AUTOFIX_CANDIDATES
      end

      def scan_all(path)
        result = @scanner.scan(path)
        result.ok? ? result.value! : []
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.scan_all", event_bus: @bus, path:)
        []
      end

      def autofix_allowed?(violation)
        return true unless @scanner.respond_to?(:should_autofix?, true)

        confidence = violation[:confidence] || violation["confidence"] || 1.0
        allowed = @scanner.__send__(:should_autofix?, violation[:rule], confidence)
        unless allowed
          @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], confidence:)
          Master::Trace::Dmesg.status("fix0", "autofix_skipped rule=#{violation[:rule]} confidence=#{confidence}")
        end
        allowed
      end

      def handle_fix_exception(error, violation, event:)
        message = error.message.to_s
        info = (@failure_taxonomy || Ground::FailureTaxonomy.new).handle(error)
        publish_fix_failure(info[:category], event, violation, message)
        Master::Trace::Dmesg.status(
          "fix0",
          "fix_error rule=#{violation[:rule]} file=#{violation[:file].to_s.delete_prefix("#{@root}/")} " \
          "category=#{info[:category]} #{error.class}: #{message[0, 160]}",
        )
        info[:category] == :transient ? :retry : :stop
      end

      def publish_fix_failure(category, event, violation, message)
        name = {
          permanent: "rule_loop:fail_fast",
          ambiguous: "rule_loop:human_intervention",
        }.fetch(category, event)
        @bus&.publish(name, rule: violation[:rule], file: violation[:file], error: message[0, 120])
      end

    end
  end
end
