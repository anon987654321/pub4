# frozen_string_literal: true

module Marketplace
  module Payments
    class DinteroWebhook
      class TransientWebhookError < StandardError; end
      class PermanentWebhookError < StandardError; end

      module_function

      def permanent!(error)
        raise PermanentWebhookError, "#{error.class}: #{error.message}"
      end

      def transient!(error)
        raise TransientWebhookError, "#{error.class}: #{error.message}"
      end
    end
  end
end
