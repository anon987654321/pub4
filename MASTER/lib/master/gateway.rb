# frozen_string_literal: true

module Master
  # Gateway — multi-channel message router.
  # Funnels messages from CLI, web, and future channels (IRC, Matrix)
  # into a single pipeline call. Channel-agnostic: ctx[:channel] tags origin.
  class Gateway
    CHANNELS = %i[cli web irc matrix api].freeze

    def initialize(pipeline:, session:, event_bus: nil)
      @pipeline = pipeline
      @session  = session
      @bus      = event_bus
      @handlers = {}
    end

    def register(channel, &handler)
      @handlers[channel.to_sym] = handler
    end

    def receive(channel:, message:, metadata: {})
      channel = channel.to_sym
      return Result.err("unknown channel: #{channel}", category: :validation) unless CHANNELS.include?(channel)

      @bus&.publish("gateway:receive", channel: channel, size: message.bytesize)

      ctx = {
        user_message: message.to_s.strip,
        channel:      channel,
        metadata:     metadata
      }

      result = @pipeline.call(Result.ok(ctx))

      if @handlers[channel]
        text = result.respond_to?(:ok?) && result.ok? ? extract_text(result) : result.to_s
        @handlers[channel].call(text, metadata)
      end

      result
    end

    def channels
      CHANNELS.map do |ch|
        status = @handlers.key?(ch) ? "active" : "available"
        "#{ch}: #{status}"
      end.join("\n")
    end

    private

    def extract_text(result)
      val = result.value!
      val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
    rescue StandardError => e
      @bus&.publish("gateway:extract_error", error: e.message)
      result.to_s
    end
  end
end
