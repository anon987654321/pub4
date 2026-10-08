# frozen_string_literal: true

module Marketplace
  module Payments
    # Honest failure when Stripe/Vipps keys are absent (MASTER: fail_fast, good_design_is_honest).
    class NotConfigured < StandardError
      def initialize(provider)
        super("#{provider} payment is not configured (set credentials or use offers-only cart)")
      end
    end
  end
end
