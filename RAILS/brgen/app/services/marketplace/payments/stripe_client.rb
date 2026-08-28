# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Marketplace
  module Payments
    # One HTTP client for every Stripe call. Checkout, refund and transfer used
    # to each open their own Net::HTTP session, so a timeout or error-parse
    # change in one would not reach the others — and none sent Idempotency-Key,
    # which is how a retried refund or transfer doubles the money movement.
    class StripeClient
      def self.get(url)
        request(Net::HTTP::Get, url)
      end

      def self.post(url, form, idempotency_key:)
        request(Net::HTTP::Post, url, form: form, idempotency_key: idempotency_key)
      end

      def self.request(klass, url, form: nil, idempotency_key: nil)
        StripeCheckout.ensure!
        uri = URI(url)
        req = klass.new(uri)
        req.basic_auth(ENV.fetch("STRIPE_SECRET_KEY"), "")
        req["Content-Type"] = "application/x-www-form-urlencoded" if form
        req["Idempotency-Key"] = idempotency_key if idempotency_key
        req.body = URI.encode_www_form(form) if form
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) { |http| http.request(req) }
        parse!(res)
      end
      private_class_method :request

      def self.parse!(res)
        data = JSON.parse(res.body)
        return data if res.is_a?(Net::HTTPSuccess)

        raise "Stripe error: #{data.dig("error", "message") || res.code}"
      rescue JSON::ParserError
        raise "Stripe error: #{res.code}"
      end
      private_class_method :parse!
    end
  end
end
