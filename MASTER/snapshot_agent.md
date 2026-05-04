# MASTER Snapshot — lib/master/agent/
Generated: 2026-05-04T10:21:42Z

## lib/master/agent/llm_dispatch.rb
```ruby
# frozen_string_literal: true

module Master
  class Agent
    # LlmDispatch — LLM routing, caching, and escalation; extracted from Agent.
    module LlmDispatch
      private

      def attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
        capable = select_capable_models(candidate_models)
        return capable if capable.respond_to?(:err?) && capable.err?

        last_response = nil
        capable.each_with_index do |selected_model, index|
          response = send_with_cache(
            selected_model,
            context + [{ role: "user", content: prompt }],
            stream:, &blk
          )
          last_response = response
          publish_llm_success(selected_model, response) if response.respond_to?(:ok?) && response.ok?
          break response unless response.respond_to?(:err?) && response.err? && index < capable.length - 1
        end
        last_response
      end

      def select_capable_models(candidates)
        capable = candidates.select { |m| replicate_model?(m) || ferrum_model?(m) || tool_capable?(m) }
        return Result.err("no tool-capable model available", category: :validation) if capable.empty?
        capable
      end

      def publish_llm_success(model, response)
        @bus&.publish("llm:response", model:, success: true, tokens_approx: response.to_s.bytesize / Session::TOKENS_PER_CHAR)
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

        @bus&.publish("llm:escalation", from: current, to: escalation_model)
        escalated = chat(
          original_message, stream: stream,
          escalation_depth: escalation_depth + 1, &blk
        )
        escalated.respond_to?(:err?) && escalated.err? ? last_response : escalated
      end

      def send_with_cache(selected_model, messages, system: nil, stream: false, &blk)
        cache_key = cache_key_for(messages.last[:content], messages[0...-1])
        breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
          @cache.fetch(cache_key, selected_model) {
            send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
          }
        }
      rescue StandardError => err
        Result.err("llm_request: #{err.message}", category: :llm_call_failure)
      end

      def send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
        sys = system || system_prompt
        if ferrum_model?(selected_model)
          return send_ferrum(selected_model, messages)
        elsif replicate_model?(selected_model)
          return send_replicate(selected_model, messages, sys:, stream:, &blk)
        end

        send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
      end

      def send_ferrum(selected_model, messages)
        alias_name = selected_model.split(":", 3).last
        response = Bridges::FerrumWebChat.new.ask(
          model_alias: alias_name, prompt: messages.last[:content]
        )
        return response if response.respond_to?(:err?) && response.err?
        Result.ok(
          response.respond_to?(:ok?) && response.ok? ? response.value! : response.to_s
        )
      end

      def send_replicate(selected_model, messages, sys:, stream:, &blk)
        reply = Bridges::Replicate.new.chat(
          model: selected_model, messages:, system: sys,
          stream:, &(stream ? blk : nil)
        )
        Result.ok(reply.content.to_s)
      end

      def send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
        chat_session = RubyLLM.chat(model: selected_model)
        final_sys = nemotron_system_prompt(selected_model, sys)
        chat_session.with_instructions(final_sys) if final_sys
        messages.each { |msg|
          chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s)
        }

        available_tools = llm_tools(selected_model)
        chat_session.with_tools(*available_tools) unless available_tools.empty?

        reply = if stream && blk
          chat_session.ask(messages.last[:content]) { |chunk|
            blk.call(chunk.content.to_s) if chunk.content
          }
        else
          chat_session.ask(messages.last[:content])
        end
        Result.ok(extract_response(reply, selected_model))
      end

      def routed_models
        return [@config.model] unless @model_router
        @model_router.fallback_chain(task_type: @config.task_type.to_sym)
      rescue StandardError => e
        @bus&.publish("llm:route_error", error: e.message) if defined?(@bus)
        [@config.model]
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      def replicate_model?(model_id)
        return false unless ENV["REPLICATE_API_KEY"].to_s.length >= MIN_API_KEY_LENGTH
        REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
      end

      def ferrum_model?(model_id)
        model_id.to_s.start_with?("ferrum:webchat:")
      end

      def tool_capable?(model_id)
        TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
      end

      def extract_response(reply, selected_model)
        return reply.to_s unless reply.respond_to?(:content)
        if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
          thinking = reply.reasoning_content.to_s.strip
          content = reply.content.to_s
          return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
        end
        reply.content.to_s
      end

      def nemotron_system_prompt(selected_model, base = nil)
        sys = base || system_prompt
        return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
        thinking_on = @config["reasoning_mode"] != "none"
        directive = thinking_on ? "detailed thinking on" : "detailed thinking off"
        [directive, sys].compact.join("\n\n")
      end

      CACHE_WINDOW = 4
      def cache_key_for(message, context)
        return Digest::SHA256.hexdigest(message) if context.empty?
        window = context.last(CACHE_WINDOW).map { |msg|
          "#{msg[:role]}:#{msg[:content]}"
        }.join("\n")
        Digest::SHA256.hexdigest("#{message}\n#{window}")
      end

      def estimate_cost(prompt)
        (prompt.bytesize / Session::TOKENS_PER_CHAR) * COST_PER_TOKEN
      end

      def llm_tools(selected_model = model)
        return [] unless tool_capable?(selected_model)
        @llm_tools ||= build_llm_tools
      end

      def build_llm_tools
        @tools.filter_map do |tool|
          wrapper = LLM_TOOL_MAP[tool.class]
          wrapper&.new(tool)
        end
      rescue StandardError => err
        @bus&.publish("agent:llm_tools_error", error: err.message)
        []
      end
    end
  end
end

```
