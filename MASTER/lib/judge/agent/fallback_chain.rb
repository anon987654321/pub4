# frozen_string_literal: true

require "set"

module Master
  module Judge
    class Agent
      module FallbackChain
        NON_RETRYABLE = %i[timeout no_api_key].freeze

        private

        def attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, image: nil, &blk)
          stage_warnings = []
          fallback_modes = mode_chain_for(candidate_models)
          last_response = nil
          timed_out_models = Set.new

          fallback_modes.each do |attempt|
            selected_model = attempt.fetch(:model)
            mode = attempt.fetch(:mode)
            next if timed_out_models.include?(selected_model)

            response = attempt_model_with_retries(
              selected_model: selected_model,
              mode: mode,
              prompt: prompt,
              context: context,
              stream: stream,
              image: image,
              &blk
            )
            if response.is_a?(Master::Result::Ok)
              publish_llm_success(selected_model, response)
              @bus&.publish("agent:stage_warnings", warnings: stage_warnings) unless stage_warnings.empty?
              return response
            end

            last_response = response
            timed_out_models << selected_model if failover_skip_model?(response)
            stage_warnings << "llm failed in #{mode} on #{selected_model}: #{response.message}"
          end

          @bus&.publish("agent:all_fallbacks_exhausted", warnings: stage_warnings)
          last_response || Result.err("all LLM fallback modes exhausted", category: :llm_call_failure)
        end

        def attempt_model_with_retries(selected_model:, mode:, prompt:, context:, stream:, image: nil, &blk)
          last_response = nil
          retry_count = @model_router&.failover_max_retries.to_i
          retry_count = 0 if retry_count.negative?
          (retry_count + 1).times do |retry_index|
            wrapped = filter_prompt(apply_reasoning_mode(prompt, mode: mode))
            response = @dispatcher.send_with_cache(
              selected_model,
              context + [{ role: "user", content: wrapped }],
              stream:, image: image, &blk
            )
            return response if response.is_a?(Master::Result::Ok)

            last_response = response
            break if failover_skip_model?(response)

            backoff_before_retry(selected_model, mode, retry_index) if retry_index < retry_count
          end
          last_response
        end

        def failover_skip_model?(response)
          response.is_a?(Master::Result::Err) && NON_RETRYABLE.include?(response.category)
        end

        def backoff_before_retry(model, mode, retry_index)
          cooldown = @model_router&.failover_cooldown_seconds.to_i
          cooldown = 300 if cooldown <= 0
          delay = cooldown * (2**retry_index)
          @bus&.publish("llm:failover_backoff", model: model, mode: mode, retry: retry_index + 1, delay: delay)
          sleep delay if ENV["MASTER_STRICT_BACKOFF"] == "1"
        end

        def mode_chain_for(candidates)
          models = Array(candidates).empty? ? [@config.model] : candidates
          primary = models.first
          modes = if @dispatcher.claude_cli_model?(primary) || @dispatcher.tool_capable?(primary)
                    [@config.reasoning_mode.to_s, "code_agent", "react"]
                  else
                    ["code_agent", "react", "direct"]
                  end
          chain = models.map { |m| { model: m, mode: modes.first } }
          chain.concat(modes.drop(1).map { |mode| { model: primary, mode: mode } })
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
            task_type: @config.task_type.to_sym
          )
          return last_response unless escalation_model
          return last_response if escalation_model.to_s == current.to_s

          @bus&.publish("llm:escalation", from: current, to: escalation_model)
          escalated = attempt_chat_with_fallbacks(
            candidate_models: [escalation_model],
            prompt: original_message,
            context: conversation_context,
            stream: stream,
            &blk
          )
          escalated.is_a?(Master::Result::Err) ? last_response : escalated
        end
      end
    end
  end
end
