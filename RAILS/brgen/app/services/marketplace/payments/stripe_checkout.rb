# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Marketplace
  module Payments
    # Stripe Checkout Session for cart/order totals.
    # Without STRIPE_SECRET_KEY → NotConfigured (never fakes success).
    class StripeCheckout
      API = "https://api.stripe.com/v1/checkout/sessions"

      def self.configured?
        ENV["STRIPE_SECRET_KEY"].to_s.strip.present?
      end

      def self.start!(order:, success_url:, cancel_url:)
        raise NotConfigured, "Stripe" unless configured?

        body = URI.encode_www_form(
          "mode" => "payment",
          "success_url" => success_url,
          "cancel_url" => cancel_url,
          "line_items[0][price_data][currency]" => (order.listing.currency || "nok").downcase,
          "line_items[0][price_data][product_data][name]" => order.listing.title.to_s.truncate(120),
          "line_items[0][price_data][unit_amount]" => order.total_cents.to_i,
          "line_items[0][quantity]" => 1,
          "client_reference_id" => order.id.to_s,
          "metadata[order_id]" => order.id.to_s
        )
        uri = URI(API)
        req = Net::HTTP::Post.new(uri)
        req.basic_auth(ENV.fetch("STRIPE_SECRET_KEY"), "")
        req["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = body
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) { |http| http.request(req) }
        data = JSON.parse(res.body)
        raise "Stripe error: #{data["error"]&.dig("message") || res.code}" unless res.is_a?(Net::HTTPSuccess)

        order.mark_payment_pending!(provider: "stripe", reference: data["id"])
        data.fetch("url")
      end
    end
  end
end
