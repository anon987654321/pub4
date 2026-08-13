# frozen_string_literal: true

module Master
  module Io
    class Gateway
      CHANNELS = %i[cli web irc matrix api].freeze

      # Contract for channel adapters.
      module Adapter
        def render(text, metadata = {})
          raise NotImplementedError, "#{self.class}#render not implemented"
        end
      end

      def initialize(pipeline:, session:, event_bus: nil, container: nil)
        @pipeline = pipeline
        @session = session
        @bus = event_bus
        @container = container
        @adapters = {}
      end

      def register(channel, adapter_or_proc = nil, &block)
        handler = adapter_or_proc || block
        @adapters[channel.to_sym] = handler
      end

      def receive(channel:, message:, metadata: {})
        channel = channel.to_sym
        return Result.err("unknown channel: #{channel}", category: :validation) unless CHANNELS.include?(channel)

        Master::Ground::Pairing.apply_remote!(channel)

        message_text = message.to_s.strip
        turn_id = "#{Process.pid}-#{Time.now.to_i}-#{rand(36**4).to_s(36)}"
        @bus&.publish("gateway:turn_start", turn_id:, channel:, message: message_text[0, 200])
        @bus&.publish("gateway:receive", channel:, size: message_text.bytesize)

        ctx = { user_message: message_text, channel:, metadata:, turn_id: }
        result = route_message(message_text, ctx)
        render_to_adapter(channel, result, metadata)

        err_msg = result.ok? ? nil : result.message&.to_s&.[](0, 120)
        @bus&.publish("gateway:turn_done", turn_id:, ok: result.ok?, error: err_msg)
        result
      end

      def route_message(message_text, ctx)
        client_actions = []
        unsub = @bus&.subscribe("client_action") do |ev|
          client_actions << ev.slice(:action, :url, :label).compact
        end
        result = if @container&.dig(:commands)
                   Master::CLI::TurnRouter.call(message: message_text, container: @container)
                 elsif @pipeline
                   @pipeline.call(Result.ok(ctx))
                 else
                   Result.err("gateway: no router", category: :infrastructure)
                 end
        unsub&.call
        client_actions.any? ? attach_client_actions(result, client_actions) : result
      end

      def render_to_adapter(channel, result, metadata)
        adapter = @adapters[channel]
        return unless adapter

        text = result.ok? ? extract_text(result) : result.to_s
        adapter.respond_to?(:render) ? adapter.render(text, metadata) : adapter.call(text, metadata)
      end

      def channels
        CHANNELS.map do |ch|
          status = @adapters.key?(ch) ? "active" : "available"
          "#{ch}: #{status}"
        end.join("\n")
      end

      private

      def extract_text(result)
        output = result.value!
        output.is_a?(Hash) && output[:rendered] ? output[:rendered] : output.to_s
      rescue StandardError => e
        @bus&.publish("gateway:extract_error", error: e.message)
        result.to_s
      end

      def attach_client_actions(result, client_actions)
        return result unless result.ok?

        value = result.value!
        merged = value.is_a?(Hash) ? value.merge(client_actions:) : { rendered: value.to_s, client_actions: }
        Result.ok(merged)
      rescue StandardError
        result
      end
    end
  end
end
