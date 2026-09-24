# frozen_string_literal: true

require "digest"
require "tempfile"
require_relative "../io/atomic_write"
require_relative "conflict_resolver"
require_relative "constants"
require_relative "fix_attempt"
require_relative "patch_applier"
require_relative "severity"
require_relative "violation"
require_relative "rule_loop/collapse_guard"
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
          soul = Master.load_yaml(Master.data_path("soul.yml"))
          abs = soul.fetch("absolute", {})
          golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          lines = ["Golden rule: #{golden}",
                    "Minimum change that eliminates the violation. Do not touch unrelated code."]
          Master::Ground::Rules.new.rules.each { |key, value| lines << "- #{key}: #{value}" }
          lines.join("\n")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "rule_loop.golden_rule")
          raise "rule_loop: constitutional preamble unreadable: #{e.class}: #{e.message}"
        end
      end

      include Master::Io::AtomicWrite
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
        @committer = options[:committer]
        @stage_commit = options.fetch(:stage_commit, false)
        @visual_image = nil
        @conflicts = ConflictResolver.new(root:, bus: @bus)
      end

      def injected_preamble=(text)
        @injected_preamble = text
      end

      # One pass: scan → fix each violating file once → return { fixed:, status: }.
      # External findings are used by rendered and convergence evidence, which
      # has already measured the artifact and therefore must not be rescanned
      # through a registry rule that knows nothing about that evidence.
      def run_once(files, external_violations: nil, image: nil)
        @visual_image = image
        violations = external_violations || scan_files(files)
        return { fixed: 0, status: :clean, breakdown: {} } if violations.empty?

        fixed = fix_batch(violations)
        status = pass_outcome(fixed)
        record_outcomes(files, status)
        @bus&.publish("rule_loop:pass", rule: @rule.id, violations: violations.size, fixed:, status:)
        { fixed:, status:, breakdown: @batch_breakdown }
      rescue StandardError => e
        @bus&.publish("rule_loop:error", rule: @rule.id, error: e.message)
        # Bus-only meant a crashed rule pass was indistinguishable from a
        # quiet one in the dmesg stream the operator actually reads.
        Master::Trace::Dmesg.status("fix0", "#{@rule.id}: #{e.class}: #{e.message[0, 90]}")
        { fixed: 0, status: :error, breakdown: { error: 1 } }
      ensure
        @visual_image = nil
      end

      private

      def scan_files(files)
        files.flat_map do |path|
          next [] unless File.exist?(path)

          result = Master::Result.wrap(@scanner.scan(path, rules: [@rule]))
          raise "rule scan failed for #{path}: #{result.error}" unless result.ok?

          ext = File.extname(path).downcase
          result.value!
                .select { |f| Severity.at_least?(f[:severity], MIN_SEVERITY) }
                .map { |f| Violation.from_finding(f, file: path, ext:) }
        end
      end

      # Returns one outcome symbol per violation, never a bare boolean: the
      # 2026-08-19 proof run reported `fixed=0` for 33 minutes with nothing in
      # the log saying whether proposals never arrived, died in reflexion, or
      # were rejected on re-scan — every non-apply collapsed to `false` before
      # the one line anyone reads. The tally of these symbols is that line.
      def fix_violation(violation)
        if needs_a_person?(violation) && !deletions_allowed?\n          @person_required = true\n          @bus&.publish("rule_loop:human_decision_required", rule: violation[:rule], file: violation[:file])\n          return :needs_person\n        end\n        return :skip_confidence unless autofix_allowed?(violation)
        return :skip_fingerprint unless fingerprint_matches?(violation)

        note_unverified_fix(violation)
        source = violation[:severity].to_sym == :error ? council_fix(violation) : request_fix(violation)
        return :no_proposal if source.to_s.strip.empty?

        verified = reflexion_verify(violation, source)
        return :reflexion_rejected unless verified
        return :consensus_rejected unless consensus_approves?(violation, verified)

        return :rejected unless apply(violation[:file], verified, violation)

        commit_applied_fix(violation)
      end

      # One fix, one commit, one push — before the next violation is touched.
      # The stage-end commit stays as the net for a fix whose own commit was
      # refused (a hook veto, a push that lost a race): the fix is applied, so
      # it must not be reported as though nothing landed, but it is also not
      # delivered until git says so, and those are different outcomes.
      def commit_applied_fix(violation)
        return :applied if @committer.nil? || stage_commit_mode?

        @committer.commit_if_dirty(
          "fix: #{@rule.id} in #{File.basename(violation[:file])}",
          findings: [violation],
          owned_paths: [violation[:file]],
        )
        :applied
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLoop.commit_applied_fix", event_bus: @bus, rule: @rule.id)
        @bus&.publish("rule_loop:commit_refused", rule: @rule.id, file: violation[:file], error: e.message[0, 160])
        :commit_refused
      end

      def stage_commit_mode?
        @stage_commit || ENV["MASTER_FIX_COMMIT_STAGE"] == "1"
      end

      # Review::Consensus fans a candidate fix out to three models and requires
      # a quorum of two before it lands. Agent#consensus constructs it and
      # nothing calls it, so the interlock read as wired for as long as it has
      # existed — the most consequential shape of this repo's inert-config
      # defect, because it is a safety gate.
      #
      # Reachable now, and off unless asked for: three model calls per fix is a
      # spend the operator opts into rather than discovers on a bill.
      def consensus_approves?(violation, candidate)
        return true unless ENV["MASTER_CONSENSUS_FIXES"] == "1"

        @agent.consensus.approve_fix?(
          prompt: "Rule #{@rule.id} on #{violation[:file]}",
          candidate:,
          violation:,
        )
      rescue StandardError => e
        # A broken quorum must not silently approve. Refuse and say why.
        Master::Ground::Swallow.log(e, context: "RuleLoop#consensus_approves?") if defined?(Master::Ground::Swallow)
        false
      end

      def apply(path, new_src, violation)
        old_src = File.read(path, encoding: "UTF-8")
        return reject_fix(path, old_src, "collapsed_content") if CollapseGuard.collapse?(@rule.id, old_src, new_src)
        before = scan_all(path)
        write_atomic(path, new_src)
        after = scan_all(path)
        return reject_fix(path, old_src, "new_violations", before:, after:) if after.size > before.size
        if (scouts = boyscout_violations(before, after, old_src, new_src)).any?
          return reject_fix(path, old_src, "boyscout_violation", violations: scouts.size)
        end
        if @conflicts.reject_higher_priority?(original_violation: violation, before:, after:, path:)
          return reject_fix(path, old_src, "higher_priority_violation")
        end
        if (failure = failing_test_for(path))
          return reject_fix(path, old_src, "test_failed", test: failure)
        end

        @bus&.publish("rule_loop:fix_applied", rule: @rule.id, file: path)
        true
      rescue StandardError => e
        @bus&.publish("rule_loop:write_error", rule: @rule.id, file: path, error: e.message)
        false
      end

      # Boyscout, line-scoped. The golden rule this loop runs under demands the
      # minimum change, so the scout's beat is only the lines the fix already
      # changed: no violation may appear there that was not there before. A
      # whole-file boyscout would command the refactors PRESERVE_FIRST forbids;
      # this is the half of the rule that is compatible with it.
      def boyscout_violations(before, after, old_src, new_src)
        before_keys = before.map { |v| [v[:rule].to_s, v[:message].to_s] }
        landed = after.reject { |v| before_keys.include?([v[:rule].to_s, v[:message].to_s]) }
        return [] if landed.empty?

        lo, hi = changed_region(old_src, new_src)
        landed.select { |v| (lo..hi).cover?(v[:line].to_i) }
      end

      # The 1-based line span the fix changed, in the NEW file's coordinates —
      # the common prefix and suffix are untouched, and the span between them
      # is where a single-hunk minimum-change fix lives.
      def changed_region(old_src, new_src)
        old_lines = old_src.lines
        new_lines = new_src.lines
        prefix = 0
        prefix += 1 while prefix < old_lines.size && prefix < new_lines.size && old_lines[prefix] == new_lines[prefix]
        suffix = 0
        limit = [old_lines.size - prefix, new_lines.size - prefix].min
        suffix += 1 while suffix < limit && old_lines[old_lines.size - 1 - suffix] == new_lines[new_lines.size - 1 - suffix]
        [prefix + 1, [new_lines.size - suffix, prefix + 1].max]
      end

      def reject_fix(path, original, reason, **details)
        write_atomic(path, original)
        @bus&.publish("rule_loop:fix_rejected", rule: @rule.id, file: path, reason:, **details)
        Master::Trace::Dmesg.status("fix0", "#{@rule.id} fix rejected, #{File.basename(path)}: #{reason}")
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
        #{visual_fix_context}

        #{SEMANTIC_PASS_CHECKLIST}

        #{ctx[:action]}

        ```#{ctx[:lang]}
        #{src}
        ```
      PROMPT
      end

      def visual_fix_context
        return "" unless @visual_image

        "Rendered evidence is attached to this request. Treat the screenshot as ground truth for the visual finding; "           "do not invent geometry, typography, or composition that the capture does not support."
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
        return if text.nil? || text.strip.empty? || CollapseGuard.sentinel?(text)

        lang = ext ? ext_language(ext) : "text"
        langs_re = Regexp.union(lang, "text", "")
        match = text.match(/```(?:#{langs_re})?\n(.*?)```/m)
        # A fence can carry the refusal too: the 2026-09-17 RAILS run wrote a
        # fenced UNCHANGED over a live view because only the bare spelling
        # was refused. The content inside the fence is the file, or it is
        # nothing.
        return if match && CollapseGuard.sentinel?(match[1])

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
        @convergence_cfg ||= begin
          rules = Master.load_yaml(Master::RULES_PATH)
          convergence = rules&.dig("thresholds", "convergence")
          raise "convergence thresholds missing: #{Master::RULES_PATH}" unless convergence.is_a?(Hash)
          convergence
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.convergence_cfg", event_bus: @bus)
        raise "rule_loop: convergence configuration unreadable: #{e.class}: #{e.message}"
      end

      def genetic_autofix_candidates
        convergence_cfg["genetic_autofix_candidates"] || RuleLoop::GENETIC_AUTOFIX_CANDIDATES
      end

      def scan_all(path)
        result = Master::Result.wrap(@scanner.scan(path))
        raise "rule scan failed for #{path}: #{result.error}" unless result.ok?

        result.value!
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.scan_all", event_bus: @bus, path:)
        raise
      end

      # A deleting transform runs only when a person asked this loop to fix, and
      # MASTER_AUTOFIX is what a person asking looks like from here: the
      # background convergence loop and the unattended ladder both leave it off.
      # An addition is visible in the diff it makes; a deletion is invisible to
      # anyone who does not already know what stood there.
      def deletions_allowed?
        ENV["MASTER_AUTOFIX"] == "1"
      end

      # A finding may say what undoing its fix costs (rules.yml
      # schema_metadata: reversibility, blast_radius). A fix nobody can undo, or
      # one that reaches past the file it was found in, waits for a person the
      # same way a deletion does.
      def needs_a_person?(violation)
        radius = violation[:blast_radius]
        files_touched = radius.is_a?(Hash) ? (radius["files_touched"] || radius[:files_touched]).to_i : 0
        violation[:reversibility].to_s == "impossible" || files_touched > 1
      end

      def autofix_allowed?(violation)
        if needs_a_person?(violation) && !deletions_allowed?
          @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], reason: :needs_a_person)
          return false
        end
        return true unless @scanner.respond_to?(:should_autofix?, true)

        confidence = violation[:confidence] || violation["confidence"] || 1.0
        allowed = @scanner.__send__(:should_autofix?, violation[:rule], confidence,
                                    allow_deletions: deletions_allowed?)
        unless allowed
          @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], confidence:)
          Master::Trace::Dmesg.status("fix0", "#{violation[:rule]} autofix skipped, confidence #{confidence}")
        end
        allowed
      end

      def handle_fix_exception(error, violation, event:)
        message = error.message.to_s
        info = (@failure_taxonomy || Ground::FailureTaxonomy.new).handle(error)
        publish_fix_failure(info[:category], event, violation, message)
        Master::Trace::Dmesg.status(
          "fix0",
          "#{violation[:rule]} fix failed, #{violation[:file].to_s.delete_prefix("#{@root}/")}: " \
          "#{info[:category]}, #{error.class}: #{message[0, 160]}",
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
