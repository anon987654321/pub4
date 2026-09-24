# frozen_string_literal: true

require "tmpdir"

module Master
  module Fix
    class RuleLoop
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
          path = violation[:file]
          return proposed_src unless File.exist?(path)

          original_src = begin
            File.read(path, encoding: "UTF-8")
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "RuleLoop.reflexion_source_read", rule: @rule.id)
            @bus&.publish("rule_loop:reflexion_rejected", rule: @rule.id, file: path,
              reason: "source read failed: #{e.message[0, 120]}")
            return
          end
          prompt = reflexion_prompt(violation, original_src, proposed_src)
          # The verdict reads a diff and answers SAFE or UNSAFE; a cheaper model
          # (MASTER_FIX_VERIFIER_MODEL) can give it, and Opus keeps the repairs.
          response = Master::Review::LLMDispatcher::ModelPin.with(ENV.fetch("MASTER_FIX_VERIFIER_MODEL", "")) do
            ask_once_agent(prompt, image: @visual_image).to_s.strip
          end
          handle_reflexion_response(response, path, proposed_src)
        rescue StandardError => e
          # A check that could not run approves nothing, as a broken quorum
          # approves nothing: the fix is refused and says why.
          Master::Ground::Swallow.log(e, context: "RuleLoop.reflexion_verify", rule: @rule.id)
          @bus&.publish("rule_loop:reflexion_rejected", rule: @rule.id, file: path, reason: "reflexion failed: #{e.message[0, 120]}")
          nil
        end

        # The verifier judges the change, so it is shown the change. It used to
        # see the first 600 characters of each version: a fix at line 113 of
        # bin/doctor was invisible, both excerpts matched, and the verifier
        # rightly called the fix byte-identical and refused it. Every repair
        # below a file's first screen died the same way.
        def reflexion_prompt(violation, original_src, proposed_src)
          <<~PROMPT
            Verify this proposed code fix is correct. Reply ONLY with "SAFE" or "UNSAFE: <reason>".

            VIOLATION: #{violation[:rule]} line #{violation[:line]} — #{violation[:message]}

            The change, as a unified diff of the whole file:
            ```diff
            #{change_under_review(original_src, proposed_src)}
            ```
          PROMPT
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
            lines = out.lines.drop_while { |line| !line.start_with?("@@") }
            return lines.join if lines.size <= REVIEW_DIFF_LINES

            "#{lines.first(REVIEW_DIFF_LINES).join}… #{lines.size - REVIEW_DIFF_LINES} more lines of diff\n"
          end
        end

        # Only SAFE approves. A reply that was neither word, a refusal, a rambling
        # paragraph, an empty string, approved the fix before.
        def handle_reflexion_response(response, path, proposed_src)
          unless response.match?(/\ASAFE\b/)
            @bus&.publish("rule_loop:reflexion_rejected", rule: @rule.id, file: path, reason: response[0, 160])
            return
          end
          @bus&.publish("rule_loop:reflexion_approved", rule: @rule.id, file: path)
          proposed_src
        end

        def council_fix(violation)
          path = violation[:file]
          return unless File.exist?(path)
          src = File.read(path, encoding: "UTF-8")
          prompt = build_prompt_for(violation:, src:, path:, style: :council)
          fix_attempt(violation, event: "rule_loop:council_error").first_code(
            prompt:,
            ext: File.extname(path).downcase,
            source: src,
            wait_context: { rule: @rule.id, file: path, mode: :council },
            image: @visual_image,
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
          prompt = build_prompt_for(violation:, src:, path:, style: :diff)
          MAX_FIX_RETRIES.times do |attempt|
            wait_before_retry(attempt, rule: @rule.id, file: path, mode: :diff)
            response = ask_agent(prompt, image: @visual_image).to_s
            next if response.strip == "UNCHANGED"
            result = PatchApplier.apply(src, response)
            return result.source if result.is_a?(PatchApplier::Success)
            return whole_file_fallback(violation:, src:, path:, reason: result.reason)
          rescue StandardError => e
            action = handle_fix_exception(e, violation, event: "rule_loop:fix_error")
            next if action == :retry
            return nil
          end
          nil
        end

        def genetic_fix(violation:, src:, path:)
          ext = File.extname(path).downcase
          prompt = build_prompt_for(violation:, src:, path:)
          candidates = fix_attempt(violation, attempts: genetic_autofix_candidates, event: "rule_loop:fix_error").codes(
            prompt:,
            ext:,
            source: src,
            wait_context: { rule: @rule.id, file: path, mode: :genetic },
            image: @visual_image,
          )
          best_candidate(Array(candidates), path)
        end

        def architect_then_fix(violation:, src:, path:)
          strong_model = routing_model_ids[:strong]
          fast_model = routing_model_ids[:fast]
          plan = architecture_plan(violation:, src:, path:, model: strong_model)
          return whole_file_fallback(violation:, src:, path:, reason: "no architecture plan") if plan.to_s.strip.empty?

          prompt = build_prompt_for(
            violation:,
            src:,
            path:,
            style: :file,
          ) + "\n\nArchitecture plan:\n#{plan}"
          response = fast_model ? ask_once_agent(prompt, model: fast_model, image: @visual_image) : ask_once_agent(prompt, image: @visual_image)
          response = extract_code(response.to_s, File.extname(path).downcase)
          return whole_file_fallback(violation:, src:, path:, reason: "no code returned") if response.to_s.strip.empty?

          response
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RuleLoop.architect_then_fix", rule: @rule.id)
          whole_file_fallback(violation:, src:, path:, reason: e.message)
        end

        def fix_attempt(violation, attempts: MAX_FIX_RETRIES, event:)
          FixAttempt.new(
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
          @bus&.publish("rule_loop:retry_wait", rule:, file:, mode:, attempt:, delay:)
          deadline = Time.now + delay
          while (remaining = deadline - Time.now).positive?
            sleep [remaining, RETRY_WAIT_SLICE].min
            Thread.pass
          end
        end

        def best_candidate(candidates, path)
          return if candidates.empty?

          original = File.read(path, encoding: "UTF-8")
          baseline = rescan_candidate(original, path)
          scored = candidates.filter_map do |candidate|
            count = rescan_candidate(candidate, path)
            [count, candidate] if count <= baseline
          end
          scored.empty? ? nil : scored.min_by(&:first).last
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RuleLoop.best_candidate", rule: @rule.id)
          nil
        end

        def rescan_candidate(candidate, path)
          Tempfile.open(["rl_score", File.extname(path)]) do |f|
            f.write(candidate); f.flush
            result = Master::Result.wrap(@scanner.scan(f.path, rules: [@rule]))
            raise "candidate rescan failed: #{result.message}" unless result.ok?

            result.value!.size
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RuleLoop.rescan_candidate", rule: @rule.id)
          raise
        end

        def whole_file_fallback(violation:, src:, path:, reason:)
          @bus&.publish("rule_loop:edit_format_fallback", rule: @rule.id, file: path, reason: reason.to_s[0, 160])
          prompt = build_prompt_for(violation:, src:, path:, style: :file)
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
          Master::Ground::Swallow.log(e, context: "RuleLoop.architecture_plan", rule: @rule.id)
          ""
        end

        def architecture_plan_prompt(violation, src, path)
          <<~PROMPT
          You are planning a safe refactor for a Ruby file.

          File: #{path}
          Rule: #{violation[:rule]}
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
            models = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml")) || {}
            tiers = models.fetch("models", {})
            {
              strong: first_model_id(tiers["strong"]),
              fast: first_model_id(tiers["fast"] || tiers["cheap"] || tiers["default"]),
            }
          rescue StandardError
            { strong: nil, fast: nil }
          end
        end

        def first_model_id(models)
          Array(models).first && Array(models).first["id"]
        end
      end
    end
  end
end
