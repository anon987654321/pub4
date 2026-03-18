# frozen_string_literal: true

require "ruby_llm"

module Master
  class Agent
    DEFAULT_CONTEXT_SIZE = 16
    COST_PER_TOKEN       = 0.000_015

    # Replicate native API — these owner prefixes route through Bridges::Replicate.
    REPLICATE_OWNERS = %w[deepseek-ai openai mistralai xai meta].freeze

    # Tool-capable model whitelist — non-matching models raise at call time.
    TOOL_CAPABLE_MODELS = %w[
      claude gpt-4 gpt-4o gemini mistral mixtral
      llama-3.1 llama-3.3 qwen command-r deepseek
      meta/meta-llama anthropic/claude openai/gpt google/gemini
    ].freeze

    NEMOTRON3_RE      = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil)
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
      configure_ruby_llm
    end

    def chat(message, stream: true, &blk)
      @session.add_message(role: :user, content: message)
      routed  = routed_models
      prompt  = apply_reasoning_mode(message)
      context = conversation_context
      @bus&.publish("llm:request", model: routed.first, tokens: message.bytesize / 4)

      last_response = routed.each_with_index do |selected_model, idx|
        assert_tool_capable!(selected_model)
        cache_key = cache_prompt_for("#{selected_model}:#{prompt}", context)
        cb = @circuit_breaker.call(estimate_cost(message)) {
          @cache.fetch(cache_key, selected_model) { do_chat(prompt, selected_model, context:, stream:, &blk) }
        }
        next if cb.respond_to?(:err?) && cb.err? && idx < routed.length - 1
        break cb
      end

      return last_response if last_response.respond_to?(:err?) && last_response.err?

      text = last_response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => e
      Result.err("agent: #{e.message}", category: :unknown)
    end

    def ask(prompt, context: nil)
      msgs = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      chat_direct(msgs)
    end

    # One-shot chat with a custom system prompt. No session, no circuit breaker.
    # Routes through Replicate bridge when model owner is in REPLICATE_OWNERS.
    def chat_raw(prompt, system: nil)
      if replicate_model?(model)
        msg = Bridges::Replicate.new.chat(
          model:    model,
          messages: [{ role: "user", content: prompt.to_s }],
          system:   system
        )
        return msg.content.to_s
      end
      c = RubyLLM.chat(model: model)
      c.with_instructions(system) if system
      msg = c.ask(prompt.to_s)
      msg.respond_to?(:content) ? msg.content.to_s : msg.to_s
    rescue StandardError => e
      raise "chat_raw: #{e.message}"
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      if on_chunk
        chat(ctx[:message].to_s, stream: true, &on_chunk)
      else
        chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first

    private

    def routed_models
      return [@config.model] unless @model_router
      @model_router.fallback_chain(task_type: @config.task_type.to_sym)
    rescue StandardError
      [@config.model]
    end

    def replicate_model?(model_id)
      return false unless ENV["REPLICATE_API_KEY"].to_s.length > 10
      REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
    end

    def assert_tool_capable!(selected_model)
      return if replicate_model?(selected_model)  # Replicate models bypass RubyLLM tools
      return if tool_capable?(selected_model)
      raise "Model '#{selected_model}' does not support function calling. " \
            "Set REPLICATE_API_KEY, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY."
    end

    def tool_capable?(model_id)
      TOOL_CAPABLE_MODELS.any? { |p| model_id.to_s.downcase.include?(p.downcase) }
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @memory.context_summary    if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def configure_ruby_llm
      RubyLLM.configure do |c|
        c.anthropic_api_key  = ENV["ANTHROPIC_API_KEY"]  if ENV["ANTHROPIC_API_KEY"].to_s.length > 10
        c.openai_api_key     = ENV["OPENAI_API_KEY"]     if ENV["OPENAI_API_KEY"].to_s.length > 10
        c.gemini_api_key     = ENV["GEMINI_API_KEY"]     if ENV["GEMINI_API_KEY"].to_s.length > 10
        c.openrouter_api_key = ENV["OPENROUTER_API_KEY"] if ENV["OPENROUTER_API_KEY"].to_s.length > 10
      end
    end

    def do_chat(message, selected_model, context:, stream:, &blk)
      if selected_model.start_with?("ferrum:webchat:")
        alias_name = selected_model.split(":", 3).last
        r = Bridges::FerrumWebChat.new.ask(model_alias: alias_name, prompt: message)
        return r.respond_to?(:value!) ? r.value! : r.to_s
      end

      if replicate_model?(selected_model)
        msgs = context + [{ role: "user", content: message }]
        msg  = Bridges::Replicate.new.chat(
          model: selected_model, messages: msgs, system: system_prompt
        )
        blk&.call(msg.content.to_s)
        return msg.content.to_s
      end

      chat = RubyLLM.chat(model: selected_model)
      chat.with_instructions(nemotron_system_prompt(selected_model)) if system_prompt
      context.each { |m| chat.add_message(role: m[:role].to_s, content: m[:content].to_s) }

      tools = llm_tools(selected_model)
      chat.with_tools(*tools) unless tools.empty?

      msg = stream && blk ? chat.ask(message) { |chunk| blk.call(chunk) } : chat.ask(message)
      extract_response(msg, selected_model)
    end

    def extract_response(msg, selected_model)
      return msg.to_s unless msg.respond_to?(:content)
      if NEMOTRON3_RE.match?(selected_model) && msg.respond_to?(:reasoning_content)
        thinking = msg.reasoning_content.to_s.strip
        content  = msg.content.to_s
        return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
      end
      msg.content.to_s
    end

    def nemotron_system_prompt(selected_model)
      base = system_prompt
      return base unless LLAMA_NEMOTRON_RE.match?(selected_model)
      thinking_on = @config["reasoning_mode"] != "none"
      directive   = thinking_on ? "detailed thinking on" : "detailed thinking off"
      [directive, base].compact.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_CONTEXT_SIZE)
      msgs = @session.messages
      return [] unless msgs.respond_to?(:each)
      msgs.last(max_messages + 1)[0...-1] || []
    end

    def cache_prompt_for(message, context)
      return message if context.empty?
      condensed = context.map { |m| "#{m[:role]}:#{m[:content]}" }.join("\n")
      "#{message}\n\n[context]\n#{condensed}"
    end

    def chat_direct(messages)
      if replicate_model?(model)
        msg = Bridges::Replicate.new.chat(model: model, messages: messages, system: system_prompt)
        return msg.content.to_s
      end
      chat = RubyLLM.chat(model: model)
      chat.with_instructions(system_prompt) if system_prompt
      messages.each { |m| chat.add_message(role: m[:role].to_s, content: m[:content].to_s) }
      chat.complete
    end

    def estimate_cost(prompt) = (prompt.bytesize / 4) * COST_PER_TOKEN

    LLM_TOOL_MAP = {
      Tools::ReadFile    => Tools::LLM::ReadFile,
      Tools::WriteFile   => Tools::LLM::WriteFile,
      Tools::StrReplace  => Tools::LLM::StrReplace,
      Tools::ListDir     => Tools::LLM::ListDir,
      Tools::SearchFiles => Tools::LLM::SearchFiles,
      Tools::Zsh         => Tools::LLM::Zsh,
      Tools::WebSearch   => Tools::LLM::WebSearch,
      Tools::AskLlm      => Tools::LLM::AskLlm,
      Tools::GitContext  => Tools::LLM::GitContext,
      Tools::AstEdit     => Tools::LLM::AstEdit,
    }.freeze

    def llm_tools(selected_model = model)
      return [] unless tool_capable?(selected_model)
      @llm_tools ||= build_llm_tools
    end

    def build_llm_tools
      @tools.filter_map do |t|
        wrapper = LLM_TOOL_MAP[t.class]
        wrapper&.new(t)
      end
    rescue StandardError => e
      @bus&.publish("agent:llm_tools_error", error: e.message)
      []
    end
  end
end
