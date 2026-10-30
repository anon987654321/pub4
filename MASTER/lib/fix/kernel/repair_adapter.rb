# frozen_string_literal: true

require "digest"
require "tempfile"

# Declare the canonical class and public compatibility constant before loading
# subordinate modules: their `class RepairLoop` bodies must reopen this exact
# object, rather than creating a second policy class beside Kernel.
module Master
  module Fix
    class Kernel
      class RepairAdapter; end unless const_defined?(:RepairAdapter, false)
    end
    # Remove a pending Zeitwerk autoload before child modules reopen RepairLoop;
    # otherwise their class declarations could recursively load the shim file.
    remove_const(:RepairLoop) if autoload?(:RepairLoop, false)
    const_set(:RepairLoop, Kernel::RepairAdapter) unless const_defined?(:RepairLoop, false)
  end
end

require_relative "../../io/atomic_write"
require_relative "../../design/authoring"
require_relative "../conflict_resolver"
require_relative "../constants"
require_relative "../attempt"
require_relative "../fix_trace"
require_relative "../patch_applier"
require_relative "../primitive_first"
require_relative "../taste_memory"
require_relative "../severity"
require_relative "../violation"
require_relative "../repair_loop/collapse_guard"
require_relative "../repair_loop/fix_strategies"
require_relative "../repair_loop/fix_verification"
require_relative "../repair_loop/outcome_tracking"
require_relative "../visual_custody_blocking"
require_relative "../best_of_n"
require_relative "../tool_breaker"
require_relative "../../review/scan/law_health"
require_relative "../repair_loop/autofix_policy"
require_relative "../run_ledger"
require_relative "../source_compile"
require_relative "../repair_loop/file_budget"
require_relative "../change_scope"
require_relative "../refusals"

module Master
  module Fix
    class Kernel
      # Single-pass fixer for one law across a set of files.
      # Kernel::ConvergenceAdapter owns convergence; this adapter repairs one batch per call.
      #
      # Fix routing (per violation severity + file size):
      #   error tier  → council_fix   (3-reviewer veto before apply)
      #   large file  → diff_fix      (unified diff patch; arch #5)
      #   small file  → genetic_fix   (N candidates, rescan, best wins; arch #9)
      class RepairAdapter
        RATE_LIMIT_SLEEP = 10
        MAX_FIX_RETRIES = 2
        RETRY_WAIT_SLICE = 0.25
        GENETIC_AUTOFIX_CANDIDATES = 3

        MIN_SEVERITY = :warning
        VISUAL_EXTENSIONS = %w[.css .scss .erb .html .htm .js .ts].freeze

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
            end
          end

          def soul_preamble
            @soul_preamble_mutex.synchronize do
              path = Master.data_path("soul.yml")
              stat = File.stat(path)
              stamp = [stat.size, stat.ino, stat.mtime.to_r]
              return @soul_preamble_cache if @soul_preamble_cache && @soul_preamble_mtime == stamp

              @soul_preamble_mtime = stamp
              @soul_preamble_cache = build_soul_preamble
            end
          end

          private

          def build_soul_preamble
            soul = Master.soul_config
            abs = soul.fetch("absolute", {})
            golden = abs["golden_law"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
            lines = ["Golden rule: #{golden}",
                      "Minimum change that eliminates the violation. Do not touch unrelated code."]
            Master::Ground::Laws.new.laws.each { |key, value| lines << "- #{key}: #{value}" }
            lines.join("\n")
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "repair_loop.golden_law")
            raise "repair_loop: constitutional preamble unreadable: #{e.class}: #{e.message}"
          end
        end

        include ::Master::Io::AtomicWrite
        include FixStrategies
        include FixVerification
        include OutcomeTracking
        include AutofixPolicy
        include FileBudget

        attr_reader :kernel

        def initialize(law:, agent:, scanner:, root:, **options)
          @kernel = options[:kernel]
          @law = law
          @agent = agent
          @scanner = scanner
          @root = root
          @bus = options[:bus]
          @learnings = options[:learnings]
          @committer = options[:committer]
          @stage_commit = options.fetch(:stage_commit, false)
          @visual_image = nil
          @visual_custody = options[:visual_custody]
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
          @batch_breakdown = {}
          receipt_attempted = false
          violations = external_violations || scan_files(files)
          if violations.empty?
            receipt_attempted = true
            return record_kernel_outcome(fixed: 0, status: :clean, breakdown: {})
          end

          fixed = fix_batch(violations)
          status = pass_outcome(fixed)
          record_outcomes(files, status)
          @bus&.publish("repair_loop:pass", law: @law.id, violations: violations.size, fixed:, status:)
          receipt_attempted = true
          record_kernel_outcome(fixed:, status:, breakdown: @batch_breakdown)
        rescue StandardError => e
          @bus&.publish("repair_loop:error", law: @law.id, error: e.message)
          # Bus-only meant a crashed rule pass was indistinguishable from a
          # quiet one in the dmesg stream the operator actually reads.
          Master::Trace::Dmesg.status("fix0", "#{@law.id}: #{e.class}: #{e.message[0, 90]}")
          applied = fixed.is_a?(Numeric) ? fixed.to_i : 0
          breakdown = if @batch_breakdown.is_a?(Hash) && !@batch_breakdown.empty?
                        @batch_breakdown.dup
                      else
                        { error: 1 }
                      end

          # Record ordinary pass failures as outcomes. If this exception came
          # from the ledger append itself, do not retry the same ambiguous write:
          # the returned status stays error and explicitly names missing evidence.
          if @kernel && !receipt_attempted
            begin
              @kernel.record_repair_outcome(
                law: @law.id, status: :error, fixed: applied, breakdown:,
              )
            rescue StandardError => receipt_error
              breakdown[:kernel_receipt_failed] = 1
              breakdown[:kernel_receipt_error_class] = receipt_error.class.name
            end
          elsif @kernel && receipt_attempted
            breakdown[:kernel_receipt_failed] = 1
          end
          { fixed: applied, status: :error, breakdown:, error: "#{e.class}: #{e.message}" }
        ensure
          @visual_image = nil
        end

        private

        def record_kernel_outcome(fixed:, status:, breakdown:)
          result = { fixed: fixed.to_i, status:, breakdown: (breakdown || {}).dup }
          @kernel&.record_repair_outcome(
            law: @law.id, status:, fixed: result[:fixed], breakdown: result[:breakdown],
          )
          result
        end

        def scan_files(files)
          files.flat_map do |path|
            next [] unless File.exist?(path)

            result = Master::Result.wrap(@scanner.scan(path, laws: [@law]))
            raise "rule scan failed for #{path}: #{result.message}" unless result.ok?

            ext = File.extname(path).downcase
            result.value!
                  .map { |f| Master::Review::Scan::LawHealth.annotate(f) }
                  .select { |f| Severity.at_least?(f[:severity], MIN_SEVERITY) }
                  .map { |f| Violation.from_finding(f, file: path, ext:) }
          end
        end

        # Returns one outcome symbol per violation, never a bare boolean: the
        # 2026-08-19 proof run reported `fixed=0` for 33 minutes with nothing in
        # the log saying whether proposals never arrived, died in reflexion, or
        # were rejected on re-scan — every non-apply collapsed to `false` before
        # the one line anyone reads. The tally of these symbols is that line.
        #
        # One repair, and when the verifier refuses it for a reason the model can act on, one
        # more with that reason in the prompt. The two-rejects-per-file limit still ends it, and
        # MASTER_FIX_RETRY=0 switches the second try off.
        RETRYABLE = %i[out_of_scope reflexion_rejected consensus_rejected rejected].freeze

        def fix_violation(violation)
          RunLedger.take_refusal
          outcome = attempt_fix(violation)
          note = RunLedger.take_refusal
          return outcome unless ENV["MASTER_FIX_RETRY"] != "0" && RETRYABLE.include?(outcome) && note

          Master::Trace::Dmesg.status("fix0", "retrying #{File.basename(violation[:file].to_s)} #{@law.id} once, told: #{note[0, 140]}")
          RunLedger.retrying(note) { attempt_fix(violation) }
        end

        def attempt_fix(violation)
          if (gap = VisualCustodyBlocking.gap_for(
            violation[:law], root: @root, path: violation[:file], custody: @visual_custody
          ))
            @person_required = true
            review = VisualCustodyBlocking.prepare_operator_review(violation)
            @bus&.publish("fix:requires_operator_decision", finding: review)
            @bus&.publish("repair_loop:operator_gap", law: violation[:law], file: violation[:file], gap:)
            Master::Trace::Dmesg.gap("fix0", "#{violation[:law]} listed, not attempted, operator-owned rendered value: #{violation[:file]}", gap)
            return :needs_person
          end
          if needs_a_person?(violation) && !deletions_allowed?
            @person_required = true
            @bus&.publish("repair_loop:human_decision_required", law: violation[:law], file: violation[:file])
            return :needs_person
          end
          return :skip_confidence unless autofix_allowed?(violation)
          return :skip_fingerprint unless fingerprint_matches?(violation)
          return :skip_rejected_twice if RunLedger.file_done?(violation[:file])

          note_unverified_fix(violation)
          FixTrace.begin_attempt(@law.id, violation[:file])
          @model_failed = false
          @model_unavailable = false
          return :model_unavailable unless @agent
          start_file_budget
          source = within_file_budget(violation) { violation[:severity].to_sym == :error ? council_fix(violation) : request_fix(violation) }
          return :file_timeout if @file_timed_out
          return (if @model_unavailable
                    :model_unavailable
                  elsif @model_failed
                    :model_failed
                  else
                    :no_proposal
                  end) if source.to_s.strip.empty?

          source = BestOfN.pick(self, violation, source, custody: @visual_custody, root: @root) if BestOfN.active?(violation, @visual_custody, tool: @law.id)
          return :no_proposal if source.to_s.strip.empty?

          FixTrace.proposed(@law.id, violation[:file], source)
          if (outside = outside_finding_range(violation, source))
            RunLedger.reject("out_of_scope", file: violation[:file], law: @law.id, bus: @bus)
            RunLedger.refused_because(outside)
            FixTrace.rejected(@law.id, violation[:file], outside)
            refuse(:scope, violation, reason: outside)
            return :out_of_scope
          end
          verified = within_file_budget(violation) { reflexion_verify(violation, source) }
          return :file_timeout if @file_timed_out
          unless verified
            RunLedger.reject("reflexion_unsafe", file: violation[:file], law: @law.id, bus: @bus)
            reason = Thread.current[:reflexion_reason].to_s
            RunLedger.refused_because(reason.start_with?("no verdict") ? "the reviewer gave no usable verdict, so the change was not accepted" : "the reviewer called it unsafe: #{reason}")
            refuse(:verifier, violation, reason:)
            return (FixTrace.rejected(@law.id, violation[:file], ["reflexion verifier refused", Thread.current[:reflexion_reason]].compact.join(": ")) && :reflexion_rejected)
          end
          unless consensus_approves?(violation, verified)
            RunLedger.reject("consensus_refused", file: violation[:file], law: @law.id, bus: @bus)
            RunLedger.refused_because("the consensus panel refused it")
            refuse(:consensus, violation, reason: "the consensus panel refused it", error: @consensus_error)
            return (FixTrace.rejected(@law.id, violation[:file], "consensus refused") && :consensus_rejected)
          end

          applied = apply(violation[:file], verified, violation)
          return :skip_fingerprint if applied == :stale
          return :rejected unless applied

          commit_applied_fix(violation)
        end

        # One fix, one commit, one push — before the next violation is touched.
        # The stage-end commit stays as the net for a fix whose own commit was
        # refused (a hook veto, a push that lost a race): the fix is applied, so
        # it must not be reported as though nothing landed, but it is also not
        # delivered until git says so, and those are different outcomes.
        def commit_applied_fix(violation)
          return :applied if @committer.nil? || stage_commit_mode?

          result = @committer.commit_if_dirty(
            "fix: #{@law.id} in #{File.basename(violation[:file])}",
            findings: [violation],
            owned_paths: [violation[:file]],
          )
          return commit_refused(violation) if result == :blocked
          return commit_refused(violation, result.message) if result.is_a?(Master::Result::Err)

          :applied
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.commit_applied_fix", event_bus: @bus, law: @law.id)
          @bus&.publish("repair_loop:commit_refused", law: @law.id, file: violation[:file], error: e.message[0, 160])
          commit_refused(violation, error: e)
        end

        # A verified fix that git would not take says why in the log: law/definition.rb's was
        # refused by the pre-commit hook and the run printed only "1 commit_refused". The
        # committer records its own refusals; a :blocked with no reason on record is the
        # committer's defect, and is recorded as one rather than left as "blocked".
        def commit_refused(violation, reason = nil, error: nil)
          if reason.nil? && error.nil?
            return :commit_refused if @committer.last_refusal

            reason = "the committer answered :blocked and recorded no reason"
          end
          why = reason.to_s.strip.lines.last(3).join(" ")[0, 300]
          refuse(:commit, violation, reason: why, error:)
          :commit_refused
        end

        # One refusal row for a violation or a path.
        def refuse(gate, target, reason: nil, error: nil)
          file = target.is_a?(String) ? target : target[:file]
          Refusals.record(gate:, file:, reason:, error:, law: @law.id, root: @root)
        end

        def stage_commit_mode?
          @stage_commit || ENV["MASTER_FIX_COMMIT_STAGE"] == "1"
        end

        # High-risk fixes always pass through the independent consensus check.
        # Lower-risk fixes may still opt into consensus with MASTER_CONSENSUS_FIXES=1.
        # A safety interlock must not become optional merely because the operator
        # forgot an environment variable.
        def consensus_required?(violation)
          %i[error critical].include?(violation[:severity].to_s.to_sym) ||
            ENV["MASTER_CONSENSUS_FIXES"] == "1"
        end

        def consensus_approves?(violation, candidate)
          @consensus_error = nil
          return true unless consensus_required?(violation)

          @agent.consensus.approve_fix?(
            prompt: "Law #{@law.id} on #{violation[:file]}",
            candidate:,
            violation:,
          )
        rescue StandardError => e
          # A broken quorum must not silently approve. Refuse and say why.
          Master::Ground::Swallow.log(e, context: "RepairLoop#consensus_approves?") if defined?(Master::Ground::Swallow)
          @consensus_error = e
          false
        end

        # The scan can be minutes older than the model answer. Check the same
        # semantic fingerprint again at the mutation boundary so a human edit made
        # while the model was thinking is never overwritten by stale work.
        def apply(path, new_src, violation)
          old_src = File.read(path, encoding: "UTF-8")
          return :stale unless fingerprint_matches?(violation)
          if (reason = VisualCompletion.change_blocker(root: @root, path:, before: old_src, after: new_src, custody: @visual_custody))
            return reject_fix(path, old_src, "visual_operator_owned", evidence: reason)
          end
          scope = ChangeScope.between(old_src, new_src)
          if (collapsed = collapsed_reason(scope, new_src))
            return reject_fix(path, old_src, "collapsed_content", evidence: collapsed)
          end
          raw_before = scan_all(path)
          log_scan_agreement(path, raw_before)
          before = check_findings(raw_before)
          write_atomic(path, new_src)
          raw_after = scan_all(path)
          after = check_findings(raw_after)
          note_semantic_drift(path, raw_before, raw_after)
          return reject_fix(path, old_src, "new_violations", before:, after:, introduced: introduced_summary(before, after, source: new_src)) if after.size > before.size
          if (scouts = boyscout_violations(before, after, scope:)).any?
            grown = scouts.first(3).map { |violation| "#{violation[:law]} line #{violation[:line]}" }.join(", ")
            return reject_fix(path, old_src, "boyscout_violation", introduced: "#{scouts.size} more: #{grown}")
          end
          if @conflicts.reject_higher_priority?(original_violation: violation, before:, after:, path:)
            blocker = @conflicts.last_blocker
            return reject_fix(path, old_src, "higher_priority_violation", introduced: "#{blocker["law"]} line #{blocker["line"]}")
          end
          if (failure = failing_test_for(path, before: old_src))
            return reject_fix(path, old_src, "test_failed", test: failure)
          end
          if (broken = SourceCompile.failure(path))
            return reject_fix(path, old_src, "does_not_compile", evidence: broken)
          end

          if (why = PrimitiveFirst.check(path, old_src, new_src, root: @root))
            return reject_fix(path, old_src, "page_scoped_override", evidence: why)
          end

          if @visual_custody && visual_source?(path)
            custody = @visual_custody.verify!(anchors: [violation[:anchor]].compact, committer: @committer)
            return reject_fix(path, old_src, "visual_regression", evidence: [custody.message, custody.gap&.clause].compact.join(", ")) unless custody.ok?
          end

          @committer&.attest_written!(path)
          @bus&.publish("repair_loop:fix_applied", law: @law.id, file: path)
          FixTrace.accepted(@law.id, path)
          true
        rescue StandardError => e
          @bus&.publish("repair_loop:write_error", law: @law.id, file: path, error: e.message)
          restore_after_error(path, old_src, e)
          refuse(:exception, path, reason: "a check after the write raised, original restored", error: e)
          false
        end

        # Any exception after the write leaves the model-written file on disk;
        # the original goes back and the fix counts as a rejection.
        def restore_after_error(path, old_src, error)
          return unless old_src

          write_atomic(path, old_src)
          @bus&.publish("repair_loop:fix_rejected", law: @law.id, file: path, reason: "exception", error: error.message[0, 160])
          FixTrace.rejected(@law.id, path, "exception #{error.class}, restored: #{error.message[0, 120]}")
        rescue StandardError => restore_error
          Master::Ground::Swallow.log(restore_error, context: "RepairLoop.restore_after_error", event_bus: @bus, law: @law.id)
        end

        # Boyscout, line-scoped. The golden rule this loop runs under demands the
        # minimum change, so the scout's beat is only the lines the fix already
        # changed: no violation may appear there that was not there before. A
        # whole-file boyscout would command the refactors PRESERVE_FIRST forbids;
        # this is the half of the rule that is compatible with it.
        #
        # "New" is what introduced_findings calls new: counted per rule, not matched
        # by message, since messages carry the numbers they measure and an eased
        # finding read as a new one. The lines are the ChangeScope's hunks, as the
        # scope guard and the house lint read them.
        def boyscout_violations(before, after, scope:)
          introduced_findings(before, after).select { |finding| scope.covers?(finding) }
        end

        def collapsed_reason(scope, new_src) = CollapseGuard.collapse(scope, law: @law.id, proposal: new_src)

        def visual_source?(path)
          VISUAL_EXTENSIONS.include?(File.extname(path).downcase) &&
            path.to_s.include?("/RAILS/") && !path.to_s.include?("/RAILS/master/")
        end

        # The gate each apply-time refusal is counted under in the pass summary.
        REJECT_GATES = {
          "visual_operator_owned" => :visual, "collapsed_content" => :collapse, "new_violations" => :new_violations,
          "boyscout_violation" => :boyscout, "higher_priority_violation" => :priority, "test_failed" => :test,
          "does_not_compile" => :compile, "page_scoped_override" => :primitive, "visual_regression" => :visual
        }.freeze

        def reject_fix(path, original, reason, **details)
          write_atomic(path, original)
          # The introduced violations are what the retry acts on, so they get room for quoted lines.
          detail = details.except(:before, :after).map { |key, value| value.to_s[0, key == :introduced ? 400 : 120] }.join(" ")
          RunLedger.reject(reason, file: path, law: @law.id, bus: @bus)
          RunLedger.refused_because([reason, detail].reject(&:empty?).join(": "))
          refuse(REJECT_GATES.fetch(reason, reason.to_sym), path, reason: [reason, detail].reject(&:empty?).join(": "))
          @bus&.publish("repair_loop:fix_rejected", law: @law.id, file: path, reason:, **details)
          FixTrace.rejected(@law.id, path, [reason, *details.except(:before, :after).values.map { |v| v.to_s[0, 120] }].join(" "))
          false
        end

        def build_prompt_for(violation:, src:, path:, style: :file)
          ctx = prompt_context_for(violation:, path:, style:)
          FixTrace.prompt(<<~PROMPT)
          #{preamble}

          File: #{File.basename(path)} (#{ctx[:lang]})
          Rule violated: #{violation[:law]}
          Line #{violation[:line]}: #{violation[:message]}
          #{ctx[:fix_line]}
          #{scale_snap_rule(violation)}
          #{visual_fix_context}
          #{VisualCompletion.prompt_context(root: @root, path:, custody: @visual_custody)}
          #{Master::Design::Authoring.context(path:, root: @root)}
          #{PrimitiveFirst.hint(violation, root: @root)}
          #{Protocol.law_prompt(@law)}

          #{SEMANTIC_PASS_CHECKLIST}

          #{RunLedger.retry_note}

          #{ctx[:action]}

          ```#{ctx[:lang]}
          #{src}
          ```
        PROMPT
        end

        def visual_fix_context
          return "" unless @visual_image

          ["Rendered evidence is attached to this request. Treat the screenshot as ground truth for the visual finding; "           "do not invent geometry, typography, or composition that the capture does not support.", TasteMemory.summary(@root)].compact.join("\n")
        end

        def prompt_context_for(violation:, path:, style:)
          # bin/doctor has no extension; its shebang says ruby, and so does
          # language_for. Labelled "text", the model answered in ruby anyway.
          lang = Master::Review::Scan::Detector::EXT_LANG.fetch(File.extname(path).downcase, nil) ||
                 Master.language_for(path) || "text"
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
            "Return a unified diff patch only (like `diff -u`). Fix the violation using the smallest evidence-backed change.\n" \
              "Do not return UNCHANGED merely because no deterministic fixer exists; use AST or semantic reasoning first.\n" \
              "Return UNCHANGED only when constitutional or verification evidence blocks the repair."
          else
            "Return ONLY the corrected file. Attempt the repair using semantic or structural reasoning when lexical automation is insufficient.\n" \
              "Return UNCHANGED only when constitutional or verification evidence blocks a concrete repair attempt."
          end
        end

        def preamble
          @injected_preamble || self.class.soul_preamble
        end

        def extract_code(text, ext = nil)
          FixTrace.reply(text)
          return if text.nil? || text.strip.empty? || CollapseGuard.sentinel?(text)
          # A refusal with its reasons: "UNCHANGED" and then why. Taken whole, it
          # was proposed as data/CANON.md, data/lexicon.yml and five other files,
          # and only the verifier stood between the prose and the tree.
          return if CollapseGuard.sentinel?(text.strip.lines.first)

          lang = ext ? ext_language(ext) : "text"
          # A file of no known language (an extensionless script) takes the
          # fence whatever it is tagged: requiring `text` or a bare fence missed
          # every ```ruby answer and handed on the whole reply, prose included.
          # Blocks are read whole, opening and closing fence together; matching
          # a lone fence paired one block's close with the next one's open.
          blocks = text.scan(/^```([\w+-]*)[ \t]*\n(.*?)^```[ \t]*$/m)
          code = blocks.find { |tag, _body| lang == "text" || [lang, "text", ""].include?(tag) }&.last
          # A fence can carry the refusal too: the 2026-09-17 RAILS run wrote a
          # fenced UNCHANGED over a live view because only the bare spelling
          # was refused. The content inside the fence is the file, or it is
          # nothing.
          return if code && CollapseGuard.sentinel?(code)

          # A source file ends in one newline. Stripped bare, every proposal
          # deleted it: the verifier refused a correct rescue fix for exactly
          # that, and apply refused another for the FINAL_NEWLINE it introduced.
          return "#{code.strip}\n" if code

          "#{text.strip}\n"
        end

        def ext_language(ext)
          Master::Review::Scan::Detector::EXT_LANG.fetch(ext.downcase, "text")
        rescue StandardError
          "text"
        end

        def genetic_autofix_candidates = GENETIC_AUTOFIX_CANDIDATES

        # A file repaired several times in a row is scanned after each fix and again before the
        # next one, on the same bytes. The scan of given content is kept, so identical bytes are
        # read once; any edit changes the digest and scans afresh.
        SCAN_MEMO_SIZE = 64

        def scan_all(path)
          key = [File.expand_path(path), Digest::SHA256.file(path).hexdigest] if File.file?(path)
          kept = key && scan_memo[key]
          return kept.dup if kept

          result = Master::Result.wrap(@scanner.scan(path))
          raise "rule scan failed for #{path}: #{result.message}" unless result.ok?

          key ? remember_scan(key, result.value!) : result.value!
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "repair_loop.scan_all", event_bus: @bus, path:)
          raise
        end

        def scan_memo = @scan_memo ||= {}

        def remember_scan(key, rows)
          scan_memo.shift if scan_memo.size >= SCAN_MEMO_SIZE
          scan_memo[key] = rows.dup
          rows
        end

        def handle_fix_exception(error, violation, event:)
          message = error.message.to_s
          info = (@failure_taxonomy || Ground::FailureTaxonomy.new).handle(error)
          @model_failed = true
          RunLedger.lane_failed(@agent.model) if @agent.respond_to?(:model)
          publish_fix_failure(info[:category], event, violation, message)
          Master::Trace::Dmesg.status(
            "fix0",
            "#{violation[:law]} fix failed, #{violation[:file].to_s.delete_prefix("#{@root}/")}: " \
            "#{info[:category]}, #{error.class}: #{message[0, 160]}",
          )
          info[:category] == :transient ? :retry : :stop
        end

        def publish_fix_failure(category, event, violation, message)
          name = {
            permanent: "repair_loop:fail_fast",
            ambiguous: "repair_loop:human_intervention",
          }.fetch(category, event)
          @bus&.publish(name, law: violation[:law], file: violation[:file], error: message[0, 120])
        end

      end
    end
    const_set(:RepairLoop, Kernel::RepairAdapter) unless const_defined?(:RepairLoop, false)
  end
end
