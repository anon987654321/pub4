# frozen_string_literal: true

require "tempfile"
require_relative "../../io/exec"
require_relative "../best_of_n"

module Master
  module Fix
    class RepairLoop
      module FixStrategies
        ARCHITECTURE_PLAN_GUIDANCE = <<~TEXT.strip
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
        TEXT

        private

        def reflexion_verify(violation, proposed_src)
          Thread.current[:reflexion_reason] = nil
          path = violation[:file]
          return proposed_src unless File.exist?(path)

          original_src = begin
            File.read(path, encoding: "UTF-8")
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "RepairLoop.reflexion_source_read", rule: @law.id)
            @bus&.publish("repair_loop:reflexion_rejected", law: @law.id, file: path,
              reason: "source read failed: #{e.message[0, 120]}")
            return
          end
          prompt = reflexion_prompt(violation, original_src, proposed_src)
          # The verdict reads a diff and answers SAFE or UNSAFE; a cheaper model
          # (MASTER_FIX_VERIFIER_MODEL) can give it, and Opus keeps the repairs.
          pin = ENV.fetch("MASTER_FIX_VERIFIER_MODEL", "")
          response = Master::Review::LLMDispatcher::ModelPin.with(pin) { ask_once_agent(prompt, image: @visual_image).to_s.strip }
          # A reply that is neither verdict (a tool call, a ramble) is asked for again, once, with the
          # reason it was refused. Only SAFE still approves, so a second non-verdict is still a refusal.
          unless reflexion_verdict?(response)
            retry_prompt = "#{prompt}\nYour last reply was not a verdict. The diff above is the whole change; do not read files or call tools. Reply with exactly one line: SAFE, or UNSAFE: <reason>."
            response = Master::Review::LLMDispatcher::ModelPin.with(pin) { ask_once_agent(retry_prompt, image: @visual_image).to_s.strip }
          end
          handle_reflexion_response(response, path, proposed_src)
        rescue StandardError => e
          # A check that could not run approves nothing, as a broken quorum
          # approves nothing: the fix is refused and says why.
          Master::Ground::Swallow.log(e, context: "RepairLoop.reflexion_verify", rule: @law.id)
          @bus&.publish("repair_loop:reflexion_rejected", rule: @law.id, file: path, reason: "reflexion failed: #{e.message[0, 120]}")
          nil
        end

        # The verifier judges the change, so it is shown the change. It used to
        # see the first 600 characters of each version: a fix at line 113 of
        # bin/doctor was invisible, both excerpts matched, and the verifier
        # rightly called the fix byte-identical and refused it. Every repair
        # below a file's first screen died the same way.
        #
        # A repair may take one of a group's findings and leave the rest for a later pass; the
        # verifier refused those as "fixes none of the cited lines". And it cannot read files, so
        # a changed signature was refused as unverifiable: the callers ride along instead.
        def reflexion_prompt(violation, original_src, proposed_src)
          <<~PROMPT
            Verify this proposed code fix is correct. Reply ONLY with "SAFE" or "UNSAFE: <reason>".
            Judge correctness, not completeness: a change that resolves some of the findings, keeps
            behaviour and introduces no defect is SAFE; the rest are left for a later pass.

            VIOLATION: #{violation[:law]} line #{violation[:line]} — #{violation[:message]}

            The change, as a unified diff of the whole file:
            ```diff
            #{change_under_review(original_src, proposed_src)}
            ```
            #{signature_callers(original_src, proposed_src)}
          PROMPT
        end

        CALLER_LINES = 30

        # Every call site in the repository of a method whose parameter list the change rewrote.
        def signature_callers(original_src, proposed_src)
          names = changed_signatures(original_src, proposed_src)
          return "" if names.empty?

          sites = names.flat_map { |name| call_sites(name) }.uniq.first(CALLER_LINES)
          listing = sites.empty? ? "(none found outside the definition)" : sites.join("\n")
          "Callers of #{names.join(", ")}, whose parameters changed:\n```\n#{listing}\n```"
        end

        DEF_LINE = /^\s*def\s+(?:self\.)?([a-z_]\w*[?!=]?)(.*)$/

        def changed_signatures(original_src, proposed_src)
          before, after = [original_src, proposed_src].map do |src|
            src.scan(DEF_LINE).to_h { |name, rest| [name, rest.strip] }
          end
          before.select { |name, params| after.key?(name) && after[name] != params }.keys
        end

        def call_sites(name)
          out, status = Master::Io::Exec.capture2e("git", "-C", Master::REPO_ROOT, "grep", "-n", "-w", "-I",
                                                   "-e", name, "--", "*.rb", "*.rake", timeout: 30)
          return [] unless status&.success?

          out.dup.force_encoding(Encoding::UTF_8).scrub.lines.map(&:strip)
             .reject { |line| line.match?(/:\s*def\s+(?:self\.)?#{Regexp.escape(name)}\b/) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.call_sites")
          []
        end

        REVIEW_DIFF_LINES = 400

        def change_under_review(original_src, proposed_src)
          return "(no change: the proposal is identical to the original)" if original_src == proposed_src

          Dir.mktmpdir("reflexion") do |dir|
            before = File.join(dir, "original")
            after = File.join(dir, "proposed")
            File.write(before, original_src)
            File.write(after, proposed_src)
            out, = Master::Io::Exec.capture2e("git", "diff", "--no-index", "--no-color", "-U5", before, after)
            # git's bytes arrive as BINARY; any non-ASCII line in them made the UTF-8 prompt
            # raise, and a verifier that cannot run refuses, so every such repair died unread.
            out = out.dup.force_encoding(Encoding::UTF_8).scrub
            lines = out.lines.drop_while { |line| !line.start_with?("@@") }
            return lines.join if lines.size <= REVIEW_DIFF_LINES

            "#{lines.first(REVIEW_DIFF_LINES).join}… #{lines.size - REVIEW_DIFF_LINES} more lines of diff\n"
          end
        end

        # Only SAFE approves. A reply that was neither word, a refusal, a rambling
        # paragraph, an empty string, approved the fix before.
        def reflexion_verdict?(response) = response.to_s.match?(/\A(?:SAFE|UNSAFE)\b/)

        def handle_reflexion_response(response, path, proposed_src)
          unless response.match?(/\ASAFE\b/)
            # The log and the retry note must not call a non-answer an UNSAFE verdict.
            reason = reflexion_verdict?(response) ? response[0, 160] : "no verdict from the reviewer (it replied: #{response[0, 100]})"
            Thread.current[:reflexion_reason] = reason
            @bus&.publish("repair_loop:reflexion_rejected", rule: @law.id, file: path, reason:)
            return
          end
          @bus&.publish("repair_loop:reflexion_approved", rule: @law.id, file: path)
          proposed_src
        end

        def council_fix(violation)
          path = violation[:file]
          return unless File.file?(path)

          src = File.read(path, encoding: "UTF-8")
          candidate_fix(
            violation:, src:, path:, style: :council,
            event: "repair_loop:council_error"
          )
        end

        def request_fix(violation)
          path = violation[:file]
          return unless File.exist?(path)
          src = File.read(path, encoding: "UTF-8")
          if src.lines.count > 200
            architect_then_fix(violation:, src:, path:)
          else
            src.bytesize > PatchApplier::DIFF_THRESHOLD ? diff_fix(violation:, src:, path:) : genetic_fix(violation:, src:, path:)
          end
        end

        def diff_fix(violation:, src:, path:)
          count = UserSimulation.candidate_count
          candidates = count.times.filter_map do |index|
            prompt = candidate_prompt(
              violation:, src:, path:, style: :diff, index:,
              suffix: "Return one unified diff for this candidate only. Do not combine it with any other candidate."
            )
            response = ask_agent(prompt, image: @visual_image).to_s
            next if response.strip == "UNCHANGED"

            applied = PatchApplier.apply(src, response)
            if applied.is_a?(PatchApplier::Success)
              @bus&.publish(
                "repair_loop:candidate_proposed",
                law: @law.id, file: path, candidate: index + 1,
                approach: UserSimulation.approach(index).fetch(:name), format: :diff
              )
              applied.source
            else
              @bus&.publish(
                "repair_loop:candidate_rejected",
                law: @law.id, file: path, candidate: index + 1,
                reason: "invalid diff: #{applied.reason.to_s[0, 140]}"
              )
              nil
            end
          rescue StandardError => e
            action = handle_fix_exception(e, violation, event: "repair_loop:fix_error")
            next if action == :retry

            nil
          end.uniq

          selected = best_candidate(candidates, path, original: src, violation:)
          return selected if selected

          candidate_fix(
            violation:, src:, path:, style: :file,
            suffix: "The independent diff candidates were unusable or rejected by verification. Propose a fresh, materially different corrected-file candidate; do not repeat or merge the rejected diffs.",
            event: "repair_loop:fix_error"
          )
        end

        def genetic_fix(violation:, src:, path:)
          candidate_fix(
            violation:, src:, path:, style: :file,
            event: "repair_loop:fix_error"
          )
        end

        def architect_then_fix(violation:, src:, path:)
          strong_model = routing_model_ids[:strong]
          fast_model = routing_model_ids[:fast]
          plan = architecture_plan(violation:, src:, path:, model: strong_model)
          suffix = if plan.to_s.strip.empty?
                     "Architecture planning produced no usable plan. Still generate distinct, bounded repair alternatives from the verified source and user-simulation oracles."
                   else
                     "Architecture plan from a separate planning pass:\n#{plan}"
                   end
          candidate_fix(
            violation:, src:, path:, style: :file, suffix:,
            model: fast_model, event: "repair_loop:fix_error"
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.architect_then_fix", rule: @law.id)
          candidate_fix(
            violation:, src:, path:, style: :file,
            suffix: "Architecture planning failed safely (#{e.class}). Propose materially different bounded alternatives without assuming a plan succeeded.",
            event: "repair_loop:fix_error"
          )
        end

        def fix_attempt(violation, attempts: MAX_FIX_RETRIES, event:)
          Attempt.new(
            agent: @agent,
            attempts:,
            wait: ->(attempt, context) { wait_before_retry(attempt, **context) },
            extractor: ->(response, ext) { extract_code(response, ext) },
            on_error: ->(error) { handle_fix_exception(error, violation, event:) },
          )
        end

        def wait_before_retry(attempt, rule:, file:, mode:)
          return unless attempt.positive?

          delay = RATE_LIMIT_SLEEP * attempt
          @bus&.publish("repair_loop:retry_wait", rule:, file:, mode:, attempt:, delay:)
          deadline = Time.now + delay
          while (remaining = deadline - Time.now).positive?
            sleep [remaining, RETRY_WAIT_SLICE].min
            Thread.pass
          end
        end

        def best_candidate(candidates, path, original: nil, violation: nil)
          return if candidates.empty?

          original ||= File.read(path, encoding: "UTF-8")
          unless File.file?(path) && File.read(path, encoding: "UTF-8") == original
            @bus&.publish(
              "repair_loop:candidate_simulation_blocked",
              law: @law.id, file: path, reason: "target changed since candidate generation"
            )
            return
          end

          baseline = rescan_candidate(original, path)
          viable = Array(candidates).map(&:to_s).reject(&:empty?).uniq.filter_map do |candidate|
            count = rescan_candidate(candidate, path)
            next if count > baseline

            { source: candidate, findings: count, diff_bytes: (candidate.bytesize - original.bytesize).abs }
          end
          return if viable.empty?

          simulation = user_simulation
          simulations = simulation.evaluate_candidates(
            path:, original:, candidates: viable.map { |row| row.fetch(:source) },
            writer: ->(target, content) { write_atomic(target, content) },
            deadline: @file_deadline
          )

          ranked = viable.each_with_index.filter_map do |row, index|
            proof = simulations[index] || { status: :unavailable, reason: "candidate has no simulation result", test_paths: [] }
            status = proof.fetch(:status).to_sym
            # A mapped test that could not provide a verdict cannot qualify a
            # candidate. Missing coverage is a separate source-only fallback,
            # always reported as unverified rather than passed.
            unavailable_with_tests = status == :unavailable && Array(proof[:test_paths]).any?
            missing_proof = proof[:reason].to_s == "candidate has no simulation result"
            if %i[regression blocked].include?(status) || unavailable_with_tests || missing_proof
              @bus&.publish(
                "repair_loop:candidate_rejected",
                law: @law.id, file: path, candidate: index + 1,
                reason: "candidate simulation #{status}: #{proof[:reason] || proof[:regressions].to_a.first || "focused proof did not clear"}"
              )
              next
            end

            [
              [row.fetch(:findings), UserSimulation.rank(status), row.fetch(:diff_bytes)],
              row.fetch(:source),
              proof
            ]
          end
          selected = ranked.min_by(&:first)
          unless selected
            @bus&.publish(
              "repair_loop:candidate_selection_blocked",
              law: @law.id, file: path, candidates: viable.size,
              reason: "every candidate introduced a test regression or focused verification was blocked"
            )
            return
          end

          proof = selected[2]
          proof_status = proof.fetch(:status).to_sym
          selection_event = proof_status == :unavailable ?
            "repair_loop:candidate_selected_unverified" : "repair_loop:candidate_selected"
          @bus&.publish(
            selection_event,
            law: @law.id, file: path, candidates: viable.size,
            status: proof_status, tests: proof.fetch(:test_paths),
            reason: proof_status == :unavailable ? proof[:reason] : nil,
            remaining_findings: selected[0][0], diff_bytes: selected[0][2],
            regressions: proof.fetch(:regressions).length,
            improvements: proof.fetch(:improvements).length
          )
          selected[1]
        rescue UserSimulation::RestoreFailure
          raise
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.best_candidate", rule: @law.id)
          nil
        end

        def rescan_candidate(candidate, path)
          Tempfile.open(["rl_score", File.extname(path)]) do |f|
            f.write(candidate); f.flush
            result = Master::Result.wrap(@scanner.scan(f.path, laws: [@law]))
            raise "candidate rescan failed: #{result.message}" unless result.ok?

            result.value!.size
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.rescan_candidate", rule: @law.id)
          raise
        end

        def user_simulation
          @user_simulation ||= UserSimulation.new(root: @root, bus: @bus)
        end

        def candidate_prompt(violation:, src:, path:, style:, index:, suffix: nil)
          approach = UserSimulation.approach(index)
          [
            build_prompt_for(violation:, src:, path:, style:),
            "Independent candidate #{index + 1}/#{UserSimulation.candidate_count}: #{approach.fetch(:name)}. Return only this candidate, not a comparison or a combined patch.",
            approach.fetch(:instruction),
            user_simulation.scenario_context(path:),
            suffix
          ].compact.reject { |part| part.to_s.strip.empty? }.join("\n\n")
        end

        def propose_candidates(violation:, src:, path:, style:, suffix: nil, event: "repair_loop:fix_error", model: nil)
          count = UserSimulation.candidate_count
          ext = File.extname(path).downcase
          count.times.filter_map do |index|
            prompt = candidate_prompt(violation:, src:, path:, style:, index:, suffix:)
            candidate = if model
                          response = ask_once_agent(prompt, model:, image: @visual_image).to_s
                          extract_code(response, ext)
                        else
                          fix_attempt(violation, attempts: 1, event:).codes(
                            prompt:, ext:, source: src,
                            wait_context: { rule: @law.id, file: path, mode: "candidate-#{index + 1}" },
                            image: @visual_image
                          ).first
                        end
            next if candidate.to_s.strip.empty? || candidate.strip == src.strip

            @bus&.publish(
              "repair_loop:candidate_proposed",
              law: @law.id, file: path, candidate: index + 1,
              approach: UserSimulation.approach(index).fetch(:name), format: style
            )
            candidate
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "RepairLoop.propose_candidates", rule: @law.id)
            handle_fix_exception(e, violation, event:)
            nil
          end.uniq
        end

        def candidate_fix(violation:, src:, path:, style:, suffix: nil, event: "repair_loop:fix_error", model: nil)
          candidates = propose_candidates(violation:, src:, path:, style:, suffix:, event:, model:)
          best_candidate(candidates, path, original: src, violation:)
        end

        def whole_file_fallback(violation:, src:, path:, reason:)
          @bus&.publish("repair_loop:edit_format_fallback", rule: @law.id, file: path, reason: reason.to_s[0, 160])
          prompt = candidate_prompt(
            violation:, src:, path:, style: :file, index: 0,
            suffix: "A previous diff could not be applied (#{reason}). Return a corrected whole-file candidate, not a diff, and keep the change within the finding."
          )
          model = routing_model_ids[:fast]
          raw = model ? ask_once_agent(prompt, model:, image: @visual_image).to_s : ask_once_agent(prompt, image: @visual_image).to_s
          # The reply, not the file: a fenced block, a sentence around it, or
          # UNCHANGED would otherwise be written over the source.
          extract_code(raw, File.extname(path).downcase)
        end

        def architecture_plan(violation:, src:, path:, model:)
          prompt = architecture_plan_prompt(violation, src, path)
          raw = model ? ask_once_agent(prompt, model:, image: @visual_image) : ask_once_agent(prompt, image: @visual_image)
          raw.to_s
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.architecture_plan", rule: @law.id)
          ""
        end

        def architecture_plan_prompt(violation, src, path)
          <<~PROMPT
          You are planning a safe refactor for a Ruby file.

          File: #{path}
          Rule: #{violation[:law]}
          Violation: line #{violation[:line]} — #{violation[:message]}

          #{ARCHITECTURE_PLAN_GUIDANCE}

          Source:
          ```ruby
          #{src}
          ```
        PROMPT
        end

        def ask_agent(prompt, image: nil)
          image ? @agent.ask(prompt, image:) : @agent.ask(prompt)
        end

        def ask_once_agent(prompt, image: nil, **options)
          return @agent.ask_once(prompt, **options) unless image

          @agent.ask_once(prompt, **options, image:)
        end

        def routing_model_ids
          @routing_model_ids ||= begin
            {
              strong: routed_fix_model(:file_write, fallback: :architecture),
              fast: routed_fix_model(:code_generation, fallback: :detect_lexical),
            }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "RepairLoop.routing_model_ids", event_bus: @bus)
            { strong: nil, fast: nil }
          end
        end

        # Repair stages use the live router, not the first YAML entry in a tier.
        # This preserves an explicit MASTER_MODEL pin while allowing Grok, GLM,
        # Claude, Gemini, Ollama and other configured lanes to participate through
        # the same availability, health, quota and failover machinery.
        def routed_fix_model(operation, fallback:)
          return unless @agent.respond_to?(:model_for)

          @agent.model_for(operation:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.routed_fix_model", operation:)
          return @agent.model_for(operation: fallback) if @agent.respond_to?(:model_for)

          nil
        end
      end
    end
  end
end
