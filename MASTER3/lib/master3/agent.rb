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
      @bus&.publish("llm:request", model: @config.model, tokens: message.bytesize / 4)

      response = @circuit_breaker.call(estimate_cost(message)) {
        @cache.fetch(message, @config.model) {
          do_chat(message, stream:, &blk)
        }
      }

      @session.add_message(role: :assistant, content: response.to_s)
      Result.ok(response)
    rescue Result::Err => e
      Result.err(e.message, category: e.category)
    rescue => e
      Result.err("agent: #{e.message}", category: :unknown)
    end

    def ask(prompt, context: nil)
      msgs = context ? context + [{ role: "user", content: prompt }] : [{ role: "user", content: prompt }]
      chat_direct(msgs)
    end

    def call(ctx)
      message = ctx[:message].to_s
      chat(message)
    end

    def model = @config.model

    private

    def configure_ruby_llm
      RubyLLM.configure do |c|
        c.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
        c.openai_api_key    = ENV["OPENAI_API_KEY"]
        c.gemini_api_key    = ENV["GEMINI_API_KEY"]
      end
    end

    def do_chat(message, stream:, &blk)
      chat = RubyLLM.chat(model: @config.model)
      @tools.each { |t| chat.with_tool(t) }

      if stream && blk
        chat.ask(message) { |chunk| blk.call(chunk) }
      else
        chat.ask(message)
      end
    end

    def chat_direct(messages)
      chat = RubyLLM.chat(model: @config.model)
      messages.each { |m| chat.add_message(role: m[:role], content: m[:content]) }
      chat.complete
    end

    def estimate_cost(message)
      (message.bytesize / 4) * 0.000_015
    end
  end
end
