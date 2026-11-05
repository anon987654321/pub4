# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Marketplace
  module Payments
    # Gives a Vipps buyer their money back for a received return.
    #
    # ePayment holds two kinds of money: reserved and captured. Brgen marks an
    # order paid on AUTHORIZED, and nothing in the tree captures a Vipps
    # payment, so most of these are still a reservation, and refund on a
    # reservation is refused. The payment is read first: captured money is
    # refunded (POST /payments/{reference}/refund), a reservation is cancelled
    # (POST /payments/{reference}/cancel), which releases it to the buyer.
    #
    # Every write carries an Idempotency-Key built from the return, so a retry
    # after a timeout cannot refund the same parcel twice. Fail-closed: no keys
    # means NotConfigured and the return keeps saying the refund is not sent.
    class VippsRefund
      def self.submit!(order:, idempotency_key:)
        raise NotConfigured, "Vipps" unless VippsCheckout.configured?

        reference = order.payment_reference.to_s
        raise ArgumentError, "order has no Vipps reference" if reference.empty?

        aggregate = call_api(:get, reference).fetch("aggregate", {})
        captured = aggregate.dig("capturedAmount", "value").to_i
        refunded = aggregate.dig("refundedAmount", "value").to_i
        return cancel!(reference, idempotency_key) if captured.zero?

        remaining = captured - refunded
        # Already refunded on Vipps' side (an earlier call landed and this
        # process died before recording it): record it, do not send it again.
        return "refund:#{reference}" unless remaining.positive?

        amount = { currency: order.payment_currency, value: [ order.total_cents.to_i, remaining ].min }
        data = call_api(:post, "#{reference}/refund", idempotency_key: idempotency_key,
                                                      body: { modificationAmount: amount })
        data["pspReference"].presence || "refund:#{reference}"
      end

      def self.cancel!(reference, idempotency_key)
        data = call_api(:post, "#{reference}/cancel", idempotency_key: "#{idempotency_key}-cancel", body: {})
        data["pspReference"].presence || "cancel:#{reference}"
      end

      def self.call_api(verb, path, idempotency_key: nil, body: nil)
        uri = URI("#{VippsCheckout.api_base}/epayment/v1/payments/#{path}")
        req = build_request(verb, uri, idempotency_key, body)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) do |http|
          http.request(req)
        end
        data = res.body.to_s.empty? ? {} : JSON.parse(res.body)
        return data if res.is_a?(Net::HTTPSuccess)

        raise ProviderError, "Vipps #{verb} #{path}: #{data['title'] || data['detail'] || res.code}"
      end

      def self.build_request(verb, uri, idempotency_key, body)
        req = verb == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{VippsCheckout.access_token}"
        req["Ocp-Apim-Subscription-Key"] = ENV.fetch("VIPPS_SUBSCRIPTION_KEY")
        req["Merchant-Serial-Number"] = ENV.fetch("VIPPS_MSN")
        req["Idempotency-Key"] = idempotency_key if idempotency_key
        return req unless body

        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
        req
      end
      private_class_method :cancel!, :build_request
    end
  end
end
