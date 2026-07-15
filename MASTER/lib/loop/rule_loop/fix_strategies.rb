# frozen_string_literal: true

module Master
  module Loop
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

          original_src = File.read(path, encoding: "UTF-8") rescue (return proposed_src)
          prompt = reflexion_prompt(violation, original_src, proposed_src)
          response = @agent.ask_once(prompt).to_s.strip
          handle_reflexion_response(response, path, proposed_src)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RuleLoop.reflexion_verify", rule: @rule.id)
          proposed_src
        end

        def reflexion_prompt(violation, original_src, proposed_src)
          <<~PROMPT
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
        end

        def handle_reflexion_response(response, path, proposed_src)
          if response.start_with?("UNSAFE")
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
          prompt = build_prompt_for(violation: violation, src: src, path: path, style: :council)
          fix_attempt(violation, event: "rule_loop:council_error").first_code(
            prompt: prompt,
            ext: File.extname(path).downcase,
            source: src,
            wait_context: { rule: @rule.id, file: path, mode: :council }
          )
        end

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

        def genetic_fix(violation:, src:, path:)
          ext = File.extname(path).downcase
          prompt = build_prompt_for(violation: violation, src: src, path: path)
          candidates = fix_attempt(violation, attempts: genetic_autofix_candidates, event: "rule_loop:fix_error").codes(
            prompt: prompt,
            ext: ext,
            source: src,
            wait_context: { rule: @rule.id, file: path, mode: :genetic }
          )
          best_candidate(Array(candidates), path)
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
          return if candidates.empty?
          return candidates.first if candidates.size == 1
          orig = File.read(path, encoding: "utf-8") rescue nil
          baseline = orig ? (rescan_candidate(orig, path) rescue nil) : nil
          scored = candidates.filter_map do |candidate|
            count = rescan_candidate(candidate, path)
            [count, candidate] unless baseline && count > baseline
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

        def whole_file_fallback(violation:, src:, path:, reason:)
          @bus&.publish("rule_loop:edit_format_fallback", rule: @rule.id, file: path, reason: reason.to_s[0, 160])
          prompt = build_prompt_for(violation: violation, src: src, path: path, style: :file)
          model = routing_model_ids[:fast]
          model ? @agent.ask_once(prompt, model: model).to_s : @agent.ask_once(prompt).to_s
        end

        def architecture_plan(violation:, src:, path:, model:)
          prompt = architecture_plan_prompt(violation, src, path)
          raw = model ? @agent.ask_once(prompt, model: model) : @agent.ask_once(prompt)
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
