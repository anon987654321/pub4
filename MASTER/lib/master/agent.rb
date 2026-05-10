# frozen_string_literal: true

require_relative "agent/llm_dispatcher"

module Master
  class Agent
    DEFAULT_MESSAGE_WINDOW_SIZE = 16

    Dependencies = Data.define(
      :config, :session, :tools, :circuit_breaker, :cache, :bus,
      :model_router, :reasoning_modes, :memory, :personality,
      :code_index, :context_window, :homeostat
    ) do
      def self.from_kwargs(config:, session:, tools:, circuit_breaker:, cache:,
                           event_bus: nil, model_router: nil, reasoning_modes: nil,
                           memory: nil, personality: nil, code_index: nil,
                           context_window: nil, homeostat: nil)
        new(
          config:, session:, tools:, circuit_breaker:, cache:, bus: event_bus,
          model_router:, reasoning_modes:, memory:, personality:,
          code_index:, context_window:, homeostat:
        )
      end
    end

    def initialize(deps:)
      @deps                              = deps
      @config, @session, @tools          = deps.config, deps.session, deps.tools
      @circuit_breaker, @cache, @bus     = deps.circuit_breaker, deps.cache, deps.bus
      @model_router, @reasoning_modes    = deps.model_router, deps.reasoning_modes
      @memory, @personality, @code_index = deps.memory, deps.personality, deps.code_index
      @context_window, @homeostat        = deps.context_window, deps.homeostat
      @dispatcher                        = LLMDispatcher.new(deps:, system_prompt: -> { system_prompt })
    end

    def chat(message, stream: true, escalation_depth: 0, &blk)
      prepare_chat_turn(message)
      candidate_models = routed_models
      prompt   = message
      context  = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / Session::TOKENS_PER_CHAR)
      @deps.homeostat&.observe(:llm_call)

      rate_err = check_rate_limit
      return rate_err if rate_err

      response = attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
      if response.is_a?(Master::Result::Err)
        @deps.homeostat&.observe(:llm_failure)
        return response
      end
      @deps.homeostat&.observe(:llm_success)
      response = maybe_escalate(response, message, stream:, escalation_depth:, &blk)

      text = response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :handler_exception)
    end

    def prepare_chat_turn(message)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
    end

    def check_rate_limit
      @circuit_breaker.check_rate!
      nil
    rescue CircuitBreaker::CircuitError => err
      Result.err(err.message, category: err.category)
    end

    def ask(prompt, context: nil, operation: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = operation ? model_for(operation:) : routed_models.first
      result = @dispatcher.send_with_cache(selected_model, messages, stream: false)
      raise StandardError, result.message if result.is_a?(Master::Result::Err)
      result.to_s
    end

    def ask_once(prompt, system: nil, model: nil)
      messages = [{ role: "user", content: prompt.to_s }]
      result   = @dispatcher.send_with_cache(model || self.model, messages, system:, stream: false)
      raise StandardError, result.message if result.is_a?(Master::Result::Err)
      result.to_s
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first
    def model=(val)
      @config["model"] = val
    end

    def model_for(operation:)
      @model_router&.constrained_for(operation:) || model
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def apply_reasoning_mode(message, mode: @config.reasoning_mode)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode:)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary if @code_index&.built?
      parts << @memory.context_summary if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end

    def attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
      stage_warnings = []
      fallback_modes = mode_chain_for(candidate_models)
      last_response = nil

      fallback_modes.each do |attempt|
        selected_model = attempt.fetch(:model)
        mode = attempt.fetch(:mode)
        wrapped = apply_reasoning_mode(prompt, mode: mode)
        response = @dispatcher.send_with_cache(
          selected_model,
          context + [{ role: "user", content: wrapped }],
          stream:, &blk
        )
        if response.is_a?(Master::Result::Ok)
          publish_llm_success(selected_model, response)
          @bus&.publish("agent:stage_warnings", warnings: stage_warnings) unless stage_warnings.empty?
          return response
        end

        last_response = response
        stage_warnings << "llm failed in #{mode} on #{selected_model}: #{response.message}"
      end

      @bus&.publish("agent:all_fallbacks_exhausted", warnings: stage_warnings)
      last_response || Result.err("all LLM fallback modes exhausted", category: :llm_call_failure)
    end

    def mode_chain_for(candidates)
      models = candidates.dup
      selected = models.first || @config.model
      if @dispatcher.claude_cli_model?(selected) || @dispatcher.tool_capable?(selected)
        return [{ model: selected, mode: @config.reasoning_mode.to_s },
                { model: selected, mode: "code_agent" },
                { model: selected, mode: "react" }]
      end

      [{ model: selected, mode: "code_agent" },
       { model: selected, mode: "react" },
       { model: selected, mode: "direct" }]
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
      escalated.is_a?(Master::Result::Err) ? last_response : escalated
    end

    def routed_models
      return [@config.model] unless @model_router
      @model_router.fallback_chain(task_type: @config.task_type.to_sym)
    rescue StandardError => e
      @bus&.publish("llm:route_error", error: e.message)
      [@config.model]
    end
  end
end
