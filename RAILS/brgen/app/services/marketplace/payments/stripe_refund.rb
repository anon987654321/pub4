# frozen_string_literal: true

module Marketplace
  module Payments
    # Refunds the original Stripe payment. Fail-closed: no key means no refund
    # row, and the UI keeps saying the money has not been sent.
    class StripeRefund
      SESSIONS = "https://api.stripe.com/v1/checkout/sessions"
      REFUNDS = "https://api.stripe.com/v1/refunds"

      def self.submit!(order:)
        StripeCheckout.ensure!
        reference = order.payment_reference.to_s
        raise ArgumentError, "order has no Stripe reference" if reference.empty?

        intent = payment_intent_for(reference)
        raise "Stripe session has no payment_intent" if intent.blank?

        data = StripeClient.post(
          REFUNDS,
          { "payment_intent" => intent, "reason" => "requested_by_customer" },
          idempotency_key: "marketplace-refund-#{order.id}"
        )
        data.fetch("id")
      end

      def self.payment_intent_for(reference)
        return reference if reference.start_with?("pi_")
        return nil unless reference.start_with?("cs_")

        session = StripeClient.get("#{SESSIONS}/#{reference}")
        intent = session["payment_intent"]
        intent.is_a?(Hash) ? intent["id"] : intent
      end
    end
  end
end
