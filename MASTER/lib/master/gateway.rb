# frozen_string_literal: true

module Master
  class Gateway
    CHANNELS = %i[cli web irc matrix api].freeze

    # Contract for channel adapters.
    module Adapter
      def render(text, metadata = {})
        raise NotImplementedError, "#{self.class}#render not implemented"
      end
    end

    def initialize(pipeline:, session:, event_bus: nil)
      @pipeline = pipeline
      @session  = session
      @bus      = event_bus
      @adapters = {}
    end

    def register(channel, adapter_or_proc = nil, &block)
      handler = adapter_or_proc || block
      @adapters[channel.to_sym] = handler
    end

    def receive(channel:, message:, metadata: {})
      channel = channel.to_sym
      return Result.err("unknown channel: #{channel}", category: :validation) unless CHANNELS.include?(channel)

      @bus&.publish("gateway:receive", channel: channel, size: message.bytesize)

      ctx = { user_message: message.to_s.strip, channel: channel, metadata: metadata }
      result = @pipeline.call(Result.ok(ctx))

      if (adapter = @adapters[channel])
        text = result.respond_to?(:ok?) && result.ok? ? extract_text(result) : result.to_s
        adapter.respond_to?(:render) ? adapter.render(text, metadata) : adapter.call(text, metadata)
      end

      result
    end

    def channels
      CHANNELS.map do |ch|
        status = @adapters.key?(ch) ? "active" : "available"
        "#{ch}: #{status}"
      end.join("
")
    end

    private

    def extract_text(result)
      output = result.value!
      output.is_a?(Hash) && output[:rendered] ? output[:rendered] : output.to_s
    rescue StandardError => e
      @bus&.publish("gateway:extract_error", error: e.message)
      result.to_s
    end
  end
end
