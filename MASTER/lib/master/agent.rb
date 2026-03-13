# frozen_string_literal: true

require "ruby_llm"

module Master
  class Agent
    DEFAULT_CONTEXT_SIZE = 16
    COST_PER_TOKEN       = 0.000_015

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
    rescue => e
      Result.err("agent: #{e.message}", category: :unknown)
    end

    def ask(prompt, context: nil)
      msgs = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      chat_direct(msgs)
    end

    # One-shot chat with a custom system prompt. No session, no circuit breaker.
    # Used by Swarm::Worker subclasses — minimal context, need-to-know only.
    def chat_raw(prompt, system: nil)
      c = RubyLLM.chat(model: model)
      c.with_instructions(system) if system
      msg = c.ask(prompt.to_s)
      msg.respond_to?(:content) ? msg.content.to_s : msg.to_s
    rescue => e
      raise "chat_raw: #{e.message}"
    end

    def call(ctx) = chat(ctx[:message].to_s)
    def model     = routed_models.first

    private

    def routed_models
      return [@config.model] unless @model_router
      @model_router.fallback_chain(task_type: @config.task_type.to_sym)
    rescue StandardError
      [@config.model]
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
        c.anthropic_api_key  = ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"].to_s.length > 10
        c.openai_api_key     = ENV["OPENAI_API_KEY"] if ENV["OPENAI_API_KEY"].to_s.length > 10
        c.gemini_api_key     = ENV["GEMINI_API_KEY"] if ENV["GEMINI_API_KEY"].to_s.length > 10
        c.openrouter_api_key = ENV["OPENROUTER_API_KEY"] if ENV["OPENROUTER_API_KEY"].to_s.length > 10
      end
    end

    def do_chat(message, selected_model, context:, stream:, &blk)
      if selected_model.start_with?("ferrum:webchat:")
        alias_name = selected_model.split(":", 3).last
        r = Bridges::FerrumWebChat.new.ask(model_alias: alias_name, prompt: message)
        return r.respond_to?(:value!) ? r.value! : r.to_s
      end

      chat = RubyLLM.chat(model: selected_model)
      chat.with_instructions(system_prompt) if system_prompt
      context.each { |m| chat.add_message(role: m[:role].to_s, content: m[:content].to_s) }
      msg = stream && blk ? chat.ask(message) { |chunk| blk.call(chunk) } : chat.ask(message)
      msg.respond_to?(:content) ? msg.content.to_s : msg.to_s
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
      chat = RubyLLM.chat(model: model)
      chat.with_instructions(system_prompt) if system_prompt
      messages.each { |m| chat.add_message(role: m[:role].to_s, content: m[:content].to_s) }
      chat.complete
    end

    def estimate_cost(prompt) = (prompt.bytesize / 4) * COST_PER_TOKEN
  end
end
