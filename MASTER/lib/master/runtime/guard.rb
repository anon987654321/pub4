# frozen_string_literal: true

module Master
  module Runtime
    class Guard
      def initialize(event_log: nil, strict: true)
        @event_log = event_log
        @strict = strict
      end

      def validate_intent!(intent)
        raise ArgumentError, "intent must be a Hash" unless intent.is_a?(Hash)
        raise ArgumentError, "intent missing :type" unless intent.fetch(:type) { intent["type"] }
        raise ArgumentError, "intent missing :actor" unless intent.fetch(:actor) { intent["actor"] }

        true
      end

      def before!(intent)
        validate_intent!(intent)
        emit("runtime:before", intent)
        true
      end

      def after!(intent, result)
        emit("runtime:after", intent.merge(result: result)) if intent.respond_to?(:merge)
        result
      end

      def failure!(intent, error)
        payload = intent.is_a?(Hash) ? intent.dup : { intent: intent.inspect }
        payload[:error_class] = error.class.name
        payload[:error_message] = error.message
        emit("runtime:failure", payload)
        raise error if @strict

        false
      end

      def around(intent)
        before!(intent)
        result = yield
        after!(intent, result)
      rescue StandardError => e
        failure!(intent, e)
      end

      private

      def emit(event, payload)
        return unless @event_log&.respond_to?(:append)

        @event_log.append(event, payload)
      end
    end
  end
end
