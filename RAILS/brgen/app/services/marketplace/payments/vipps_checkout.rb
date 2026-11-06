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

      # The test endpoint is never a production fallback. Choose the environment
      # explicitly so a missing or invalid production setting fails closed.
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
        raise ArgumentError, "order is not payable" unless order.respond_to?(:startable?) && order.startable?

        token = access_token
        reference = reference_for(order)
        payload = {
          amount: { currency: order.payment_currency, value: order.total_cents.to_i },
          paymentMethod: { type: "WALLET" },
          reference: reference,
          returnUrl: return_url,
          userFlow: "WEB_REDIRECT",
          paymentDescription: order.payment_description.to_s.truncate(100)
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
        raise ProviderError, "Vipps error: #{data["title"] || data["message"] || res.code}" unless res.is_a?(Net::HTTPSuccess)

        order.mark_payment_pending!(provider: "vipps", reference: reference)
        data.dig("redirectUrl") || data.dig("url") || raise(ProviderError, "Vipps response missing redirectUrl")
      end

      # Names the table the id belongs to: a basket (Marketplace::Checkout) and
      # an order share an id sequence only by accident. A payable may name its
      # own kind (Takeaway::Order says "takeaway"), since its model_name element
      # is "order" too.
      def self.reference_for(payable)
        kind = payable.try(:payment_reference_kind) || payable.model_name.element
        "brgen-#{kind}-#{payable.id}-#{SecureRandom.hex(4)}"
      end

      # A token lives for its expires_in (about a day), so one is fetched per
      # lifetime rather than per checkout; a minute is kept back so a token
      # never expires between the read and the payment call. Keyed by host and
      # client so the test and live environments never share one.
      def self.access_token
        token_key = "vipps-epayment-token:#{api_base}:#{ENV.fetch('VIPPS_EPAYMENT_CLIENT_ID')}"
        cached = Rails.cache.read(token_key)
        return cached if cached

        grant = fetch_access_token
        token = grant.fetch("access_token")
        lifetime = grant["expires_in"].to_i - 60
        Rails.cache.write(token_key, token, expires_in: lifetime.seconds) if lifetime.positive?
        token
      end

      # A refused token call names its status; it used to surface as a KeyError
      # on the missing access_token, or a JSON error on an HTML error page.
      def self.fetch_access_token
        uri = URI("#{api_base}/accesstoken/get")
        req = token_request(uri)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 15) do |http|
          http.request(req)
        end
        raise ProviderError, "Vipps access token refused: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      end

      def self.token_request(uri)
        req = Net::HTTP::Post.new(uri)
        req["client_id"] = ENV.fetch("VIPPS_EPAYMENT_CLIENT_ID")
        req["client_secret"] = ENV.fetch("VIPPS_EPAYMENT_CLIENT_SECRET")
        req["Ocp-Apim-Subscription-Key"] = ENV.fetch("VIPPS_SUBSCRIPTION_KEY")
        req["Merchant-Serial-Number"] = ENV.fetch("VIPPS_MSN")
        req
      end
      # access_token is public: VippsRefund signs its calls with the same token.
      private_class_method :fetch_access_token, :token_request
    end
  end
end
