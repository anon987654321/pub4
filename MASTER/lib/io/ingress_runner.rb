# frozen_string_literal: true

module Master
  module Io
    # Shared turn execution for bridge, webhook, and cron ingress.
    module IngressRunner
      module_function

      def run_turn(container:, message:, metadata: {}, elevated: false)
        gateway = container[:gateway]
        return Result.err("gateway unavailable", category: :infrastructure) unless gateway

        with_fiber(elevated:) do
          gateway.receive(channel: :api, message: message.to_s, metadata:)
        end
      end

      # Both keys are written, so an untrusted turn cannot inherit elevation
      # already sitting on the calling fiber.
      def with_fiber(elevated:)
        Fiber[:master_elevated] = elevated ? true : nil
        Fiber[:master_visitor] = elevated ? nil : true
        yield
      ensure
        Fiber[:master_elevated] = nil
        Fiber[:master_visitor] = nil
        Fiber[:master_paired] = nil
        Fiber[:master_pair_subject] = nil
      end
    end
  end
end
