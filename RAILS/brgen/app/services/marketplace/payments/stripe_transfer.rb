# frozen_string_literal: true

module Marketplace
  module Payments
    # Moves held funds to a shop's connected Stripe account. Without a Connect
    # destination the transfer is refused, not faked. Separate charges and
    # transfers (Checkout lands on the platform; this pushes onward) — reversing
    # is how a later refund recovers the money from the connected account.
    class StripeTransfer
      API = "https://api.stripe.com/v1/transfers"
      ACCOUNT = /\Aacct_[A-Za-z0-9]+\z/

      def self.submit!(payout:)
        StripeCheckout.ensure!
        destination = Marketplace::Store.where(id: payout.store_id).pick(:stripe_connect_id).to_s
        raise NotConfigured, "Stripe Connect" unless destination.match?(ACCOUNT)

        data = StripeClient.post(
          API,
          {
            "amount" => payout.amount_cents.to_i,
            "currency" => payout.currency.to_s.downcase,
            "destination" => destination,
            "metadata[payout_id]" => payout.id.to_s,
            "transfer_group" => payout.order_id.present? ? "order_#{payout.order_id}" : "payout_#{payout.id}"
          },
          idempotency_key: "marketplace-payout-#{payout.id}"
        )
        data.fetch("id")
      end

      def self.reverse!(payout:)
        StripeCheckout.ensure!
        transfer_id = payout.stripe_transfer_id.to_s
        raise ArgumentError, "payout has no Stripe transfer" if transfer_id.empty?

        data = StripeClient.post(
          "#{API}/#{transfer_id}/reversals",
          { "amount" => payout.amount_cents.to_i },
          idempotency_key: "marketplace-payout-reverse-#{payout.id}"
        )
        data.fetch("id")
      end
    end
  end
end
