# frozen_string_literal: true

require "ruby_llm"

module Master3
  class Agent
    def initialize(config:, session:, tools:, circuit_breaker:, cache:, event_bus: nil)
      @config          = config
      @session         = session
      @tools           = tools
      @circuit_breaker = circuit_breaker
      @cache           = cache
      @bus             = event_bus
      configure_ruby_llm
    end

    def chat(message, stream: true, &blk)
      @session.add_message(role: :user, content: message)
      @bus&.publish("llm:request", model:, tokens: message.bytesize / 4)

      context = conversation_context
      cache_prompt = cache_prompt_for(message, context)

      cb = @circuit_breaker.call(estimate_cost(message)) {
        @cache.fetch(cache_prompt, model) { do_chat(message, context:, stream:, &blk) }
      }

      return cb if cb.respond_to?(:err?) && cb.err?

      response = cb.to_s
      @session.add_message(role: :assistant, content: response)
      Result.ok(response)
    rescue => e
      Result.err("agent: #{e.message}", category: :unknown)
    end

    def ask(prompt, context: nil)
      msgs = Array(context) + [{ role: "user", content: prompt }]
      chat_direct(msgs)
    end

    def call(ctx) = chat(ctx[:message].to_s)
    def model     = @config.model

    private

    def configure_ruby_llm
      RubyLLM.configure do |c|
        c.anthropic_api_key    = ENV["ANTHROPIC_API_KEY"]    if ENV["ANTHROPIC_API_KEY"].to_s.length > 10
        c.openai_api_key       = ENV["OPENAI_API_KEY"]       if ENV["OPENAI_API_KEY"].to_s.length > 10
        c.gemini_api_key       = ENV["GEMINI_API_KEY"]       if ENV["GEMINI_API_KEY"].to_s.length > 10
        c.openrouter_api_key   = ENV["OPENROUTER_API_KEY"]   if ENV["OPENROUTER_API_KEY"].to_s.length > 10
      end
    end

    def do_chat(message, context:, stream:, &blk)
      chat = RubyLLM.chat(model:)
      context.each do |msg|
        chat.add_message(role: msg[:role].to_s, content: msg[:content].to_s)
      end

      # tools used by Execute stage directly
      msg = stream && blk ? chat.ask(message) { |chunk| blk.call(chunk) } : chat.ask(message)
      msg.respond_to?(:content) ? msg.content.to_s : msg.to_s
    end

    def conversation_context(max_messages: 16)
      @session.messages.last(max_messages + 1)[0...-1] || []
    end

    def cache_prompt_for(message, context)
      return message if context.empty?

      condensed = context.map { |m| "#{m[:role]}:#{m[:content]}" }.join("\n")
      "#{message}\n\n[context]\n#{condensed}"
    end

    def chat_direct(messages)
      chat = RubyLLM.chat(model:)
      messages.each { |m| chat.add_message(role: m[:role].to_s, content: m[:content].to_s) }
      chat.complete
    end

    def estimate_cost(prompt) = (prompt.bytesize / 4) * 0.000_015
  end
end
