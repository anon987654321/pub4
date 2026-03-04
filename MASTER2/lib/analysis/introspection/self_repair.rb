# frozen_string_literal: true

module Analysis
  module Introspection
    class SelfRepair
      def initialize(repairer:, logger: nil)
        @repairer = repairer
        @logger = logger
      end

      def call(payload)
        return payload unless eligible?(payload)

        attempt_repair(payload)
      end

      def eligible?(payload)
        return false if payload.nil?

        payload.respond_to?(:to_h) || payload.is_a?(Hash)
      end

      private

      attr_reader :repairer, :logger

      def attempt_repair(payload)
        repairer.call(payload)
      rescue StandardError => e
        log_error(e, payload)
        payload
      end

      def log_error(error, payload)
        return unless logger

        logger.error(
          "SelfRepair failed: #{error.class}: #{error.message} payload=#{safe_inspect(payload)}"
        )
      rescue StandardError
        nil
      end

      def safe_inspect(obj)
        obj.inspect
      rescue StandardError
        "<uninspectable:#{obj.class}>"
      end
    end
  end
end