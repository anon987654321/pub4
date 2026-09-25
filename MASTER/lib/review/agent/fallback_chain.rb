# frozen_string_literal: true

require "set"

module Master
  module Review
    class Agent
      module FallbackChain
        # Default when there is no router or no config; the live list comes from
        # data/models.yml via ModelRouter#failover_skip_categories.
        NON_RETRYABLE = %i[timeout no_api_key].freeze

        private

        def attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, image: nil, &blk)
          stage_warnings = []
          queue = mode_chain_for(candidate_models)
          last_response = nil
          timed_out_models = Set.new
          attempted_models = Set.new

          until queue.empty?
            attempt = queue.shift
            attempted_models << attempt.fetch(:model)
            response = try_fallback_attempt(attempt, timed_out_models:, stage_warnings:, prompt:, context:, stream:, image:, &blk)
            next unless response

            if response.is_a?(Master::Result::Ok)
              answered = response.model || attempt.fetch(:model)
              follow_answering_model(answered)
              publish_llm_success(answered, response)
              @bus&.publish("agent:stage_warnings", warnings: stage_warnings) unless stage_warnings.empty?
              return response.with_model(answered)
            end
            last_response = response
            queue = refresh_fallback_queue(queue, attempted_models)
          end

          @bus&.publish("agent:all_fallbacks_exhausted", warnings: stage_warnings)
          exhausted_result(last_response, stage_warnings)
        end

        # OpenCrabs' rule: when the chosen model fails and another answers, the
        # session moves to the one that answered and says so once, instead of
        # asking the failed one first on every turn. Not saved to config, so the
        # next boot tries the operator's choice again.
        def follow_answering_model(answered)
          return if @pinned_model.nil? || answered == @pinned_model
          return unless Io::ModelSkipCache.skipped?(@pinned_model)

          Trace::Dmesg.once("model0", "#{@pinned_model} failed, switched to #{answered}")
          @pinned_model = answered
        end

        # A turn no model answered ends on one line naming each model tried and
        # its reason, rather than the last failure alone.
        def exhausted_result(last_response, stage_warnings)
          return Result.err("all LLM fallback modes exhausted", category: :llm_call_failure) unless last_response

          tried = stage_warnings.filter_map { |line| line[/\Allm failed in \S+ on (.*)\z/m, 1] }
                                .uniq { |line| line.split(": ", 2).first }
          return last_response if tried.size < 2

          Result.err("no model answered: #{tried.map { |line| line.lines.first.strip[0, 90] }.join('; ')}",
                     category: last_response.category)
        end

        def try_fallback_attempt(attempt, timed_out_models:, stage_warnings:, prompt:, context:, stream:, image:, &blk)
          selected_model = attempt.fetch(:model)
          mode = attempt.fetch(:mode)
          return if skip_fallback_attempt?(selected_model, timed_out_models:, stage_warnings:)

          response = attempt_model_with_retries(
            selected_model:,
            mode:,
            prompt:,
            context:,
            stream:,
            image:,
            &blk
          )
          return response if response.is_a?(Master::Result::Ok)

          record_fallback_failure(response, selected_model, mode:, timed_out_models:, stage_warnings:)
          response
        end

        def skip_fallback_attempt?(selected_model, timed_out_models:, stage_warnings:)
          return true if timed_out_models.include?(selected_model)
          return false unless Io::ModelSkipCache.skipped?(selected_model)

          reason = Io::ModelSkipCache.skip_reason(selected_model)
          stage_warnings << "skipped #{selected_model} (recent failure: #{reason})"
          true
        end

        def record_fallback_failure(response, selected_model, mode:, timed_out_models:, stage_warnings:)
          if failover_skip_model?(response)
            timed_out_models << selected_model
            record_failover_skip(selected_model, response)
          end
          stage_warnings << "llm failed in #{mode} on #{selected_model}: #{response.message}"
        end

        def attempt_model_with_retries(selected_model:, mode:, prompt:, context:, stream:, image: nil, &blk)
          last_response = nil
          retry_count = @model_router&.failover_max_retries.to_i
          retry_count = 0 if retry_count.negative?
          (retry_count + 1).times do |retry_index|
            response = dispatch_retry(selected_model:, mode:, prompt:, context:, stream:, image:, retry_index:, retry_count:, &blk)
            return response if response.is_a?(Master::Result::Ok)

            last_response = response
            break if failover_skip_model?(response) || permanent_failure?(response) || offline?(response)

            backoff_before_retry(selected_model, mode, retry_index) if retry_index < retry_count
          end
          last_response
        end

        def dispatch_retry(selected_model:, mode:, prompt:, context:, stream:, image:, retry_index:, retry_count:, &blk)
          @bus&.publish("llm:retry_attempt", model: selected_model, mode:, attempt: retry_index + 1,
                                          max: retry_count + 1)
          wrapped = apply_reasoning_mode(prompt, mode:)
          @dispatcher.send_with_cache(
            selected_model,
            context + [{ role: "user", content: wrapped }],
            stream:, image:, &blk
          )
        end

        def failover_skip_model?(response)
          return false unless response.is_a?(Master::Result::Err)

          skip_categories.include?(response.category)
        end

        # A refused request fails identically on every retry, so retrying it only
        # spends the 30s and 60s backoff. The next model or mode still gets a turn.
        def permanent_failure?(response)
          response.is_a?(Master::Result::Err) && response.permanent?
        end

        def offline?(response)
          response.is_a?(Master::Result::Err) && response.category == :offline
        end

        # Re-read the live route after a failed provider. A model may disappear
        # or recover while the turn is running; newly reachable lanes join the
        # queue without asking a previously attempted lane twice.
        def refresh_fallback_queue(queue, attempted_models)
          return queue unless @model_router

          task_type = @config.task_type.to_s.empty? ? :exploration : @config.task_type.to_sym
          live = @model_router.fallback_chain(task_type:)
          fresh = Array(live).reject { |model| attempted_models.include?(model) }
          current = queue.map { |attempt| [attempt[:model], attempt[:mode]] }.to_set
          queue + mode_chain_for(fresh).reject { |attempt| current.include?([attempt[:model], attempt[:mode]]) }
        rescue StandardError => e
          @bus&.publish("llm:dynamic_route_error", error: e.message)
          queue
        end

        def skip_categories
          return NON_RETRYABLE unless @model_router.respond_to?(:failover_skip_categories)

          @model_router.failover_skip_categories || NON_RETRYABLE
        end

        # The tiers exist for provider 429s, so the sleep is the point. It is
        # opt-out rather than opt-in because a gate that must be switched on is
        # a gate nothing switches on: the old MASTER_STRICT_BACKOFF switch was
        # set in no environment, no test and no rc.d script, so every retry went
        # straight back at the provider while this method published an event
        # saying it had waited. `slept:` rides along so the trace cannot claim a
        # wait that did not happen.
        def backoff_before_retry(model, mode, retry_index)
          tiers = @model_router&.failover_cooldown_tiers || [30, 60, 300]
          delay = tiers[[retry_index, tiers.size - 1].min]
          slept = ENV["MASTER_NO_BACKOFF"] != "1"
          @bus&.publish("llm:failover_backoff", model:, mode:, retry: retry_index + 1, delay:,
                                                tiered: true, slept:)
          sleep delay if slept
        end

        def record_failover_skip(model, response)
          cat = response.respond_to?(:category) ? response.category : :provider_error
          Io::ModelSkipCache.skip!(model, reason: response.message, category: cat)
          @bus&.publish("llm:failover_skip", model:, category: cat, ttl_ms: Io::ModelSkipCache.skip_ttl_ms)
        end

        def mode_chain_for(candidates)
          models = Array(candidates).empty? ? [@config.model] : candidates
          primary = models.first
          modes = if (@dispatcher.respond_to?(:agy_model?) && @dispatcher.agy_model?(primary)) ||
                     (@dispatcher.respond_to?(:claude_cli_model?) && @dispatcher.claude_cli_model?(primary)) ||
                     @dispatcher.tool_capable?(primary)
                    [@config.reasoning_mode.to_s, "code_agent", "react"]
                  else
                    %w[code_agent react direct]
                  end
          chain = models.map { |m| { model: m, mode: modes.first } }
          chain.concat(modes.drop(1).map { |mode| { model: primary, mode: } })
          chain
        end

        def publish_llm_success(model, response)
          tokens_approx = Trace::Session.estimate_tokens(response)
          @bus&.publish("llm:response", model:, success: true, tokens_approx:)
        end

        def maybe_escalate(last_response, original_message, stream:, escalation_depth:, &blk)
          return last_response unless @model_router
          return last_response if escalation_depth >= 2

          current = routed_models.first
          escalation_model = @model_router.escalate_if_low_confidence(
            last_response.to_s,
            current_model: current,
            task_type: @config.task_type.to_sym,
          )
          return last_response unless escalation_model
          return last_response if escalation_model.to_s == current.to_s

          escalated = attempt_escalation(escalation_model, current, original_message, stream, &blk)
          escalated.is_a?(Master::Result::Err) ? last_response : escalated
        end

        def attempt_escalation(escalation_model, current, original_message, stream, &blk)
          @bus&.publish("llm:escalation", from: current, to: escalation_model)
          attempt_chat_with_fallbacks(
            candidate_models: [escalation_model],
            prompt: original_message,
            context: conversation_context,
            stream:,
            &blk
          )
        end
      end
    end
  end
end
