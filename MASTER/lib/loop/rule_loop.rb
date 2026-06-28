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
require_relative "rule_loop/fix_strategies"
require_relative "rule_loop_support"

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
          abs.fetch("code_rules", {}).each { |key, value| lines << "- #{key}: #{value}" }
          abs.fetch("aesthetic_rules", {}).each { |key, value| lines << "- #{key}: #{value}" }
          lines.join("\n")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "rule_loop.golden_rule")
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end

      include Master::Ground::AtomicWrite
      include Master::Loop::FixHelpers
      include FixStrategies
      include RuleLoopSupport

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
        status = fixed > 0 ? :fixed : :stuck
        record_outcomes(files, fixed > 0 ? :fixed : :stuck)
        @bus&.publish("rule_loop:pass", rule: @rule.id, violations: violations.size, fixed:, status:)
        { fixed:, status: }
      rescue StandardError => e
        @bus&.publish("rule_loop:error", rule: @rule.id, error: e.message)
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

      def fix_batch(violations)
        violations.uniq { |violation| violation[:file] }.count { |violation| fix_violation(violation) }
      end

      def fix_violation(violation)
        return false unless autofix_allowed?(violation) && fingerprint_matches?(violation)

        note_unverified_fix(violation)
        source = violation[:severity].to_sym == :error ? council_fix(violation) : request_fix(violation)
        source = reflexion_verify(violation, source) if source
        source ? apply(violation[:file], source, violation) : false
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
        false
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
          "Return a unified diff patch only (like `diff -u`). Fix only the violation.\n" \
            "If unsafe to autofix, return exactly: UNCHANGED"
        else
          "Return ONLY the corrected file. If unsafe to autofix, return exactly: UNCHANGED"
        end
      end

      def preamble
        @injected_preamble || self.class.soul_preamble
      end

    end
  end
end
