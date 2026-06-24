# frozen_string_literal: true

require_relative "llm_dispatcher"
require_relative "consensus"
require_relative "prompt_filter"
require_relative "agent/model_selector"
require_relative "agent/prompt_builder"
require_relative "agent/fallback_chain"

module Master
  module Judge
    class Agent
      include PromptFilter
      include ModelSelector
      include PromptBuilder
      include FallbackChain

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
        @deps = deps
        @config, @session, @tools = deps.config, deps.session, deps.tools
        @circuit_breaker, @cache, @bus = deps.circuit_breaker, deps.cache, deps.bus
        @model_router, @reasoning_modes = deps.model_router, deps.reasoning_modes
        @memory, @personality, @code_index = deps.memory, deps.personality, deps.code_index
        @context_window, @homeostat = deps.context_window, deps.homeostat
        @constitution = nil
        @dispatcher = Master::Judge::LLMDispatcher.new(deps:, system_prompt: -> { { static: static_prompt, dynamic: dynamic_prompt } })
      end

      def wire_constitution(constitution) = @constitution = constitution

      def chat(message, image: nil, stream: true, escalation_depth: 0, &blk)
        prepare_chat_turn(message)
        candidate_models = routed_models(message)
        selected_model = candidate_models.first
        prompt   = topic_anchored(message)
        context  = conversation_context
        tokens_approx = Trace::Session.estimate_tokens(message)
        @bus&.publish("llm:request", model: selected_model, tokens: tokens_approx)
        @deps.homeostat&.observe(:llm_call)

        rate_err = check_rate_limit(selected_model)
        return rate_err if rate_err

        response = attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, image: image, &blk)
        if response.is_a?(Master::Result::Err)
          @deps.homeostat&.observe(:llm_failure)
          return response
        end
        @deps.homeostat&.observe(:llm_success)
        response = maybe_escalate(response, message, stream:, escalation_depth:, &blk)

        text = response.to_s
        PhantomRecovery.detect(text, bus: @bus)

        @session.add_message(role: :assistant, content: text)
        publish_ctx_footer(selected_model)
        Result.ok(text)
      rescue StandardError => chat_error
        Result.err("agent: #{chat_error.message}", category: :handler_exception)
      end

      def prepare_chat_turn(message)
        @context_window&.check_and_compact!
        @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
        @session.add_message(role: :user, content: message)
      end

      def check_rate_limit(model_id = nil)
        @circuit_breaker.check_rate!(model_id) if @circuit_breaker.respond_to?(:check_rate!)
        nil
      rescue Reach::CircuitBreaker::CircuitError => err
        Result.err(err.message, category: err.category)
      end

      def publish_ctx_footer(model_id)
        est = @session.respond_to?(:token_est) ? @session.token_est : 0
        limit = Master::CTX_WINDOW_SIZE
        pct = limit.positive? ? ((est.to_f / limit) * 100).round(1) : 0
        @bus&.publish("ctx:footer", model: model_id, token_est: est, limit:, pct:)
      end
      private :prepare_chat_turn, :check_rate_limit, :publish_ctx_footer

      def ask(prompt, context: nil, operation: nil, image: nil)
        messages = Array(context) + [{ role: "user", content: filter_prompt(apply_reasoning_mode(prompt)) }]
        selected_model = operation ? model_for(operation:) : routed_models.first
        result = @dispatcher.send_with_cache(selected_model, messages, stream: false, image: image)
        raise StandardError, result.message if result.is_a?(Master::Result::Err)
        result.to_s
      end

      def ask_once(prompt, system: nil, model: nil, image: nil)
        messages = [{ role: "user", content: filter_prompt(prompt) }]
        result   = @dispatcher.send_with_cache(model || self.model, messages, system: filter_prompt(system), stream: false, image: image)
        raise StandardError, result.message if result.is_a?(Master::Result::Err)
        result.to_s
      end

      def consensus
        @consensus ||= Master::Judge::Consensus.new(agent: self, event_bus: @bus)
      end

      def call(ctx)
        on_chunk = ctx[:on_chunk]
        task_type = ctx[:task_type]&.to_s
        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
        with_task_type(task_type) do
          if on_chunk
            chat(ctx[:message].to_s, image: image, stream: true) { |chunk| on_chunk.call(chunk) }
          else
            chat(ctx[:message].to_s, image: image)
          end
        end
      end

      def model = routed_models.first
      def model=(val)
        @config["model"] = val
      end

      def with_model(override, &blk)
        @model_mutex ||= Mutex.new
        @model_mutex.synchronize do
          prev = model
          self.model = override
          blk.call
        ensure
          self.model = prev
        end
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
    end
  end
end
