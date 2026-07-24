# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"

module Marketplace
  module Payments
    # Vipps MobilePay ePayment create-payment.
    # Login OAuth (VIPPS_CLIENT_*) is separate; eCom needs VIPPS_EPAYMENT_* + MSN.
    # Without keys → NotConfigured (never fakes success).
    class VippsCheckout
      def self.configured?
        ENV["VIPPS_EPAYMENT_CLIENT_ID"].to_s.strip.present? &&
          ENV["VIPPS_EPAYMENT_CLIENT_SECRET"].to_s.strip.present? &&
          ENV["VIPPS_MSN"].to_s.strip.present? &&
          ENV["VIPPS_SUBSCRIPTION_KEY"].to_s.strip.present?
      end

      def self.api_base
        ENV.fetch("VIPPS_API_BASE", "https://apitest.vipps.no")
      end

      def self.start!(order:, return_url:)
        raise NotConfigured, "Vipps" unless configured?

        token = access_token
        reference = "brgen-order-#{order.id}-#{SecureRandom.hex(4)}"
        payload = {
          amount: { currency: (order.listing.currency || "NOK"), value: order.total_cents.to_i },
          paymentMethod: { type: "WALLET" },
          reference: reference,
          returnUrl: return_url,
          userFlow: "WEB_REDIRECT",
          paymentDescription: order.listing.title.to_s.truncate(100),
        }
        uri = URI("#{api_base}/epayment/v1/payments")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Ocp-Apim-Subscription-Key"] = ENV.fetch("VIPPS_SUBSCRIPTION_KEY")
        req["Merchant-Serial-Number"] = ENV.fetch("VIPPS_MSN")
        req["Idempotency-Key"] = reference
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) { |http| http.request(req) }
        data = JSON.parse(res.body)
        raise "Vipps error: #{data["title"] || data["message"] || res.code}" unless res.is_a?(Net::HTTPSuccess)

        order.mark_payment_pending!(provider: "vipps", reference: reference)
        data.dig("redirectUrl") || data.dig("url") || raise("Vipps response missing redirectUrl")
      end

      def self.access_token
        uri = URI("#{api_base}/accesstoken/get")
        req = Net::HTTP::Post.new(uri)
        req["client_id"] = ENV.fetch("VIPPS_EPAYMENT_CLIENT_ID")
        req["client_secret"] = ENV.fetch("VIPPS_EPAYMENT_CLIENT_SECRET")
        req["Ocp-Apim-Subscription-Key"] = ENV.fetch("VIPPS_SUBSCRIPTION_KEY")
        req["Merchant-Serial-Number"] = ENV.fetch("VIPPS_MSN")
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 15) { |http| http.request(req) }
        data = JSON.parse(res.body)
        data.fetch("access_token")
      end
      private_class_method :access_token
    end
  end
end
