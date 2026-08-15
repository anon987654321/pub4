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

      TEST_API_BASE = "https://apitest.vipps.no"
      LIVE_API_BASE = "https://api.vipps.no"

      # The test endpoint is not a safe default in production.
      #
      # This used to be a bare ENV.fetch with the test host as its fallback. A
      # production box missing one variable would then take a customer through a
      # complete, successful-looking checkout against Vipps' test environment:
      # a redirect, a confirmation, an order marked paid, and no money. The
      # class comment above says "never fakes success", and unconfigured it did
      # not -- but *mis*configured it faked success perfectly, which is worse,
      # because nothing raises and nobody looks.
      #
      # So the environment is now chosen rather than defaulted. Production uses
      # the live host unless VIPPS_TEST_MODE is explicitly set, and an explicit
      # VIPPS_API_BASE pointing at test in production has to say so out loud.
      def self.api_base
        explicit = ENV["VIPPS_API_BASE"].to_s.strip
        return explicit if explicit.present? && (!production? || test_mode? || !explicit.include?("apitest"))

        if explicit.present? && explicit.include?("apitest") && production? && !test_mode?
          raise NotConfigured,
                "Vipps (VIPPS_API_BASE points at the test endpoint in production; " \
                "set VIPPS_TEST_MODE=1 to allow it deliberately)"
        end

        production? && !test_mode? ? LIVE_API_BASE : TEST_API_BASE
      end

      def self.test_mode?
        ENV["VIPPS_TEST_MODE"].to_s.strip.present?
      end

      def self.production?
        defined?(Rails) && Rails.respond_to?(:env) ? Rails.env.production? : false
      end

      def self.start!(order:, return_url:)
        raise NotConfigured, "Vipps" unless configured?
        raise ArgumentError, "order is not payable" unless order.respond_to?(:payable?) && order.payable?

        token = access_token
        reference = "brgen-order-#{order.id}-#{SecureRandom.hex(4)}"
        payload = {
          amount: { currency: order.payment_currency, value: order.total_cents.to_i },
          paymentMethod: { type: "WALLET" },
          reference: reference,
          returnUrl: return_url,
          userFlow: "WEB_REDIRECT",
          paymentDescription: order.payment_description.to_s.truncate(100),
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
