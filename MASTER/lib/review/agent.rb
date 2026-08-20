# frozen_string_literal: true

require_relative "llm_dispatcher"
require_relative "consensus"
require_relative "prompt_filter"
require_relative "agent/model_selector"
require_relative "agent/model_override"
require_relative "agent/prompt_builder"
require_relative "agent/fallback_chain"

module Master
  module Review
    class Agent
      include PromptFilter
      include ModelSelector
      include ModelOverride
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
        @dispatcher = Master::Review::LLMDispatcher.new(deps:, system_prompt: -> { { static: static_prompt, dynamic: dynamic_prompt } })
      end

      def wire_constitution(constitution) = @constitution = constitution

      def chat(message, image: nil, stream: true, escalation_depth: 0, task_type: nil, &blk)
        prepare_chat_turn(message)
        dispatch = prepare_chat_dispatch(message, task_type)

        rate_err = check_rate_limit(dispatch[:selected_model])
        return rate_err if rate_err

        response = dispatch_chat_response(dispatch, stream:, image:, &blk)
        return response if response.is_a?(Master::Result::Err)

        finalize_chat_response(response, message, dispatch:, image:, stream:, escalation_depth:, task_type:, &blk)
      rescue StandardError => chat_error
        Result.err("agent: #{chat_error.message}", category: :handler_exception)
      end

      def ask(prompt, context: nil, operation: nil, image: nil, temperature: nil)
        messages = Array(context) + [{ role: "user", content: filter_prompt(apply_reasoning_mode(prompt)) }]
        selected_model = operation ? model_for(operation:) : routed_models.first
        result = @dispatcher.send_with_cache(selected_model, messages, stream: false, image:, temperature:)
        result = retry_on_broke_lane(result, selected_model, messages, image:, temperature:)
        raise StandardError, result.message if result.is_a?(Master::Result::Err)
        result.to_s
      end

# A category a retry cannot cure but a different lane can. chat/call
# walk the full fallback chain; the single-shot doors (ask, ask_once)
# take exactly one hop to the claude_code chain head instead — and the
# categories that qualify come from the same models.yml
# fallback_policy.on the chain reads, so the two lists cannot drift.
SINGLE_CALL_FAILOVER = %i[budget rate_limit timeout no_api_key].freeze

      def ask_once(prompt, system: nil, model: nil, image: nil, temperature: nil)
        messages = [{ role: "user", content: filter_prompt(prompt) }]
        chosen = model || self.model
        result = @dispatcher.send_with_cache(chosen, messages, system: filter_prompt(system), stream: false, image:, temperature:)
        result = retry_on_broke_lane(result, chosen, messages, system: filter_prompt(system), image:, temperature:)
        raise StandardError, result.message if result.is_a?(Master::Result::Err)
        result.to_s
      end

      def consensus
        @consensus ||= Master::Review::Consensus.new(agent: self, event_bus: @bus)
      end

      def call(ctx)
        on_chunk = ctx[:on_chunk]
        task_type = ctx[:task_type]&.to_s
        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
        @felt_sense = ctx[:felt_sense]
        message = ctx[:message].to_s
        with_task_type(task_type) do
          if on_chunk
            chat(message, image:, stream: true, task_type:) { |chunk| on_chunk.call(chunk) }
          else
            chat(message, image:, task_type:)
          end
        end
      ensure
        @felt_sense = nil
      end

      def wire_context_window(ctx_window)
        @context_window = ctx_window
      end

      private

def single_call_failover_categories
  @single_call_failover_categories ||=
    (@model_router.respond_to?(:failover_skip_categories) && @model_router.failover_skip_categories) ||
    SINGLE_CALL_FAILOVER
end

      # Both single-shot doors — ask and ask_once — used to raise on the first
      # broke model. One hop to the claude_code chain head on any category a
      # retry cannot cure; the 2026-08-20 proof runs showed the error-severity
      # rules die in ask (via FixAttempt) after ask_once was fixed alone.
      def retry_on_broke_lane(result, chosen, messages, system: nil, image: nil, temperature: nil)
        return result unless result.is_a?(Master::Result::Err) && single_call_failover_categories.include?(result.category)

        fallback = single_call_fallback_model
        return result unless fallback && fallback != chosen

        @bus&.publish("llm:ask_once_failover", from: chosen, to: fallback, category: result.category)
        @dispatcher.send_with_cache(fallback, messages, system:, stream: false, image:, temperature:)
      end

      # The claude_code chain's head — read through ModelRouter, the one
      # sanctioned models.yml reader, so retiring the lane retires the failover.
      def single_call_fallback_model
        @single_call_fallback_model ||= (@model_router.single_call_fallback_model if @model_router.respond_to?(:single_call_fallback_model))
      rescue StandardError
        nil
      end

      def dispatch_chat_response(dispatch, stream:, image:, &blk)
        response = attempt_chat_with_fallbacks(candidate_models: dispatch[:candidate_models], prompt: dispatch[:prompt],
          context: dispatch[:context], stream:, image:, &blk)
        @deps.homeostat&.observe(response.is_a?(Master::Result::Err) ? :llm_failure : :llm_success)
        response
      end

      def finalize_chat_response(response, message, dispatch:, image:, stream:, escalation_depth:, task_type:, &blk)
        response = maybe_escalate(response, message, stream:, escalation_depth:, &blk)

        text = response.to_s
        recovery_result = handle_phantom_recovery(text, message:, image:, stream:, escalation_depth:, task_type:, &blk)
        return recovery_result if recovery_result

        @session.add_message(role: :assistant, content: text)
        publish_ctx_footer(dispatch[:selected_model])
        Result.ok(text)
      end

      def prepare_chat_turn(message)
        @context_window&.check_and_compact!
        @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
        @session.add_message(role: :user, content: message)
      end

      def check_rate_limit(model_id = nil)
        @circuit_breaker.check_rate!(model_id) if @circuit_breaker.respond_to?(:check_rate!)
        nil
      rescue Io::CircuitBreaker::CircuitError => err
        Result.err(err.message, category: err.category)
      end

      def publish_ctx_footer(model_id)
        est = @session.respond_to?(:token_est) ? @session.token_est : 0
        limit = Master.context_window(model_id)
        pct = limit.positive? ? ((est.to_f / limit) * 100).round(1) : 0
        @bus&.publish("ctx:footer", model: model_id, token_est: est, limit:, pct:)
      end

      def prepare_chat_dispatch(message, task_type)
        candidate_models = routed_models(message, task_type:)
        selected_model = candidate_models.first
        @bus&.publish("llm:routed", model: selected_model, task_type: task_type || @config.task_type, reason: "routing")
        prompt = topic_anchored(message)
        context = conversation_context
        tokens_approx = Trace::Session.estimate_tokens(message)
        @bus&.publish("llm:request", model: selected_model, tokens: tokens_approx)
        @deps.homeostat&.observe(:llm_call)
        { candidate_models:, selected_model:, prompt:, context: }
      end

      def handle_phantom_recovery(text, message:, image:, stream:, escalation_depth:, task_type:, &blk)
        recovery = Master::PhantomRecovery.handle(text, bus: @bus, session: @session)
        case recovery[:action]
        when :discard
          Result.err("phantom recovery: discarded repetitive response", category: :policy)
        when :escalate
          chat(message, image:, stream:, escalation_depth: escalation_depth + 1, task_type:, &blk) if escalation_depth < 2
        when :halt
          Result.err("phantom recovery: halted after repeated phantom patterns", category: :policy)
        end
      end

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
