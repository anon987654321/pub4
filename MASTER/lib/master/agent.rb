# frozen_string_literal: true

require "ruby_llm"
require "digest"

module Master
  class Agent
    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN              = 0.000_015

    # Replicate native API — these owner prefixes route through Bridges::Replicate.
    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze

    # Tool-capable model whitelist — anchored regex, not substring match.
    # See note at tool_capable? for why the previous `include?` check was unsafe.
    TOOL_CAPABLE_RE = %r{
      \A(?:
        (?:claude|gpt-4|gpt-4o|gemini|mistral|mixtral)
        | (?:llama-3\.[13])
        | (?:qwen|command-r|deepseek|stepfun|nvidia|nemotron)
        | (?:meta/meta-llama.+)
        | (?:anthropic/claude.+)
        | (?:openai/gpt.+)
        | (?:google/gemini.+)
      )(?:[:@/\-.].+)?\z
    }ix.freeze

    MAX_TOOL_TURNS     = 5
    MIN_API_KEY_LENGTH = 20
    TOOL_CALL_RE       = /(?:<use_tool>\s*(.*?)\s*<\/use_tool>|^ACTION:\s*(\{.*?\})\s*$|^TOOL:\s*(\{.*?\})\s*$)/m.freeze

    NEMOTRON3_RE      = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil, code_index: nil, context_window: nil)
      @code_index      = code_index
      @config          = config
      @session         = session
      @tools           = tools
      @circuit_breaker = circuit_breaker
      @cache           = cache
      @bus             = event_bus
      @model_router    = model_router
      @reasoning_modes = reasoning_modes
      @memory          = memory
      @personality     = personality
      @context_window  = context_window
      # RubyLLM is configured once at module boot (see Master.configure_providers!).
      # Per-agent init was globally mutating shared state across agents.
    end

    def chat(message, stream: true, escalation_attempted: false, &blk)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
      candidate_models = routed_models
      prompt           = apply_reasoning_mode(message)
      context          = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / 4)

      begin
        @circuit_breaker.check_rate!
      rescue CircuitBreaker::CircuitError => rate_err
        return Result.err(rate_err.message, category: rate_err.category)
      end

      last_response = attempt_chat_with_fallbacks(candidate_models, prompt, context, stream, &blk)

      return last_response if last_response.respond_to?(:err?) && last_response.err?

      last_response = maybe_escalate(last_response, prompt, context, message, stream, escalation_attempted, &blk)

      text = last_response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :unknown)
    end

    # Result-returning companion to #ask. Prefer this for pipeline stages.
    # See #ask for the legacy string/raise API retained for AutoLoop/Sweep/scan-rule callers.
    def ask_result(prompt, context: nil)
      text = ask(prompt, context: context)
      Result.ok(text)
    rescue StandardError => ask_err
      Result.err("ask: #{ask_err.message}", category: :unknown)
    end

    def ask(prompt, context: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = routed_models.first
      result = _send_llm_request_with_cache_and_breaker(selected_model, messages, stream: false)
      result.to_s
    end

    # One-shot chat with a custom system prompt. No session.
    def ask_once(prompt, system: nil)
      _send_llm_request_with_cache_and_breaker(model, [{ role: "user", content: prompt.to_s }], system: system, stream: false).to_s
    end

    # One-shot with explicit model override (used by swarm workers with PREFERRED_MODEL).
    def ask_once_with_model(prompt, model:, system: nil)
      _send_llm_request_with_cache_and_breaker(model, [{ role: "user", content: prompt.to_s }], system: system, stream: false).to_s
    end

    def call(ctx)
      on_chunk  = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first

    def model=(val)
      @config["model"] = val # This sets the base model; model_router may override this for specific task types.
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    # Skip models that cannot call tools instead of raising. A single
    # non-tool-capable candidate used to abort the whole fallback chain.
    def attempt_chat_with_fallbacks(candidate_models, prompt, context, stream, &blk)
      capable = candidate_models.select { |m| replicate_model?(m) || ferrum_model?(m) || tool_capable?(m) }
      if capable.empty?
        return Result.err(
          "no tool-capable model available. Set REPLICATE_API_KEY, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY.",
          category: :validation
        )
      end

      last_response = nil
      capable.each_with_index do |selected_model, index|
        response = _send_llm_request_with_cache_and_breaker(selected_model, context + [{ role: "user", content: prompt }], stream: stream, &blk)
        last_response = response
        next if response.respond_to?(:err?) && response.err? && index < capable.length - 1
        if response.respond_to?(:ok?) && response.ok?
          @bus&.publish("llm:response", model: selected_model, success: true, tokens_approx: response.to_s.bytesize / 4)
        end
        break response
      end
      last_response
    end

    # Escalates once per chat call.
    def maybe_escalate(last_response, prompt, context, original_message, stream, escalation_attempted, &blk)
      return last_response unless @model_router
      return last_response if escalation_attempted

      escalation_model = @model_router.escalate_if_low_confidence(
        last_response.to_s,
        current_model: routed_models.first,
        task_type: @config.task_type.to_sym
      )
      return last_response unless escalation_model

      @bus&.publish("llm:escalation", from: routed_models.first, to: escalation_model)
      # Recursively call chat with the escalated model and mark escalation as attempted.
      escalated_result = chat(
        original_message,
        stream: stream,
        escalation_attempted: true,
        &blk
      )
      escalated_result.respond_to?(:err?) && escalated_result.err? ? last_response : escalated_result
    end

    def _send_llm_request_with_cache_and_breaker(selected_model, messages, system: nil, stream: false, &blk)
      cache_key = cache_key_for(messages.last[:content], messages[0...-1])
      breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
        @cache.fetch(cache_key, selected_model) {
          _send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
        }
      }
    rescue StandardError => err
      Result.err("llm_request: #{err.message}", category: :llm_call_failure)
    end

    def _send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
      current_system_prompt = system || system_prompt
      if ferrum_model?(selected_model)
        alias_name = selected_model.split(":", 3).last
        response   = Bridges::FerrumWebChat.new.ask(model_alias: alias_name, prompt: messages.last[:content])
        return Result.ok(response.respond_to?(:value!) ? response.value! : response.to_s)
      elsif replicate_model?(selected_model)
        reply = Bridges::Replicate.new.chat(
          model: selected_model, messages: messages, system: current_system_prompt,
          stream: stream, &(stream ? blk : nil)
        )
        return Result.ok(reply.content.to_s)
      end

      chat_session = RubyLLM.chat(model: selected_model)
      final_system_prompt = nemotron_system_prompt(selected_model, current_system_prompt)
      chat_session.with_instructions(final_system_prompt) if final_system_prompt
      messages.each { |msg| chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s) }

      available_tools = llm_tools(selected_model)
      chat_session.with_tools(*available_tools) unless available_tools.empty?

      reply = if stream && blk
        chat_session.ask(messages.last[:content]) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
      else
        chat_session.ask(messages.last[:content])
      end
      Result.ok(extract_response(reply, selected_model))
    end

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def routed_models
      return [@config.model] unless @model_router
      @model_router.fallback_chain(task_type: @config.task_type.to_sym)
    rescue StandardError
      [@config.model]
    end

    # Use per-model breaker when registry available, global breaker otherwise.
    def breaker_for(model_id)
      @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
    end

    def replicate_model?(model_id)
      return false unless ENV["REPLICATE_API_KEY"].to_s.length >= MIN_API_KEY_LENGTH
      REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
    end

    def ferrum_model?(model_id) = model_id.to_s.start_with?("ferrum:webchat:")

    # Anchored match against a real pattern. `"gpt-4-whatever"` no longer matches
    # `"claude"` just because both strings contain common substrings.
    def tool_capable?(model_id)
      TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary        if @code_index&.built?
      parts << @memory.context_summary    if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def extract_response(reply, selected_model)
      return reply.to_s unless reply.respond_to?(:content)
      if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
        thinking = reply.reasoning_content.to_s.strip
        content  = reply.content.to_s
        return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
      end
      reply.content.to_s
    end

    def nemotron_system_prompt(selected_model, base_system_prompt = nil)
      base = base_system_prompt || system_prompt
      return base unless LLAMA_NEMOTRON_RE.match?(selected_model)
      thinking_on = @config["reasoning_mode"] != "none"
      directive   = thinking_on ? "detailed thinking on" : "detailed thinking off"
      [directive, base].compact.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end

    # Hash-based cache key. Previously concatenated the full conversation
    # context into the key, producing multi-KB keys that almost never hit
    # across turns. SHA256 of (prompt + rolling 4-message window) is stable
    # for retries, narrow enough to actually collide on repeats, bounded size.
    # Ref: arxiv:2601.23088 on semantic-cache collision tradeoffs; we use
    # exact-hash over a bounded window to avoid fuzzy-hash vulnerabilities.
    CACHE_WINDOW = 4
    def cache_key_for(message, context)
      return Digest::SHA256.hexdigest(message) if context.empty?
      window = context.last(CACHE_WINDOW).map { |msg| "#{msg[:role]}:#{msg[:content]}" }.join("\n")
      Digest::SHA256.hexdigest("#{message}\n#{window}")
    end

    def estimate_cost(prompt) = (prompt.bytesize / 4) * COST_PER_TOKEN

    LLM_TOOL_MAP = {
      Tools::ReadFile         => Tools::LLM::ReadFile,
      Tools::WriteFile        => Tools::LLM::WriteFile,
      Tools::StrReplace       => Tools::LLM::StrReplace,
      Tools::ListDir          => Tools::LLM::ListDir,
      Tools::SearchFiles      => Tools::LLM::SearchFiles,
      Tools::Shell            => Tools::LLM::Shell,
      Tools::WebSearch        => Tools::LLM::WebSearch,
      Tools::AskLlm           => Tools::LLM::AskLlm,
      Tools::GitContext       => Tools::LLM::GitContext,
      Tools::AstEdit          => Tools::LLM::AstEdit,
      Tools::SearchKnowledge  => Tools::LLM::SearchKnowledge,
    }.freeze

    def llm_tools(selected_model = model)
      return [] unless tool_capable?(selected_model)
      @llm_tools ||= build_llm_tools
    end

    def build_llm_tools
      @tools.filter_map do |tool|
        wrapper = LLM_TOOL_MAP[tool.class]
        wrapper&.new(tool)
      end
    rescue StandardError => tools_error
      @bus&.publish("agent:llm_tools_error", error: tools_error.message)
      []
    end
  end
end