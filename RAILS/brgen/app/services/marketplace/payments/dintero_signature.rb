# frozen_string_literal: true

require "openssl"
require "uri"

module Marketplace
  module Payments
    module DinteroSignature
      MAX_AGE = 5.minutes

      module_function

      def valid_callback?(header:, request:, now: Time.current)
        timestamp, signature = parse(header)
        return false if timestamp.nil? || signature.blank?
        return false if now.to_i - timestamp > MAX_AGE.to_i

        expected = callback_header(
          timestamp: timestamp,
          method: request.request_method,
          url: request.url
        )
        secure_compare(expected, header)
      end

      def valid_webhook?(header:, body:)
        return false if header.to_s.empty?

        expected = OpenSSL::HMAC.hexdigest(
          "SHA1",
          ENV["DINTERO_HOOK_SECRET"].to_s,
          body.to_s
        )
        secure_compare(expected, header.to_s)
      end

      def callback_header(timestamp:, method:, url:)
        parsed = URI.parse(url)
        query = URI.decode_www_form(parsed.query.to_s).sort_by(&:first)
        query_string = URI.encode_www_form(query)
        payload = [
          timestamp,
          ENV.fetch("DINTERO_ACCOUNT_ID"),
          method.to_s.upcase,
          parsed.hostname,
          parsed.path,
          query_string
        ].join("\n")
        signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("DINTERO_CALLBACK_SECRET"), payload)
        "t=#{timestamp},v0-hmac-sha256=#{signature}"
      end

      def parse(header)
        values = header.to_s.split(",").to_h do |part|
          key, value = part.split("=", 2)
          [ key.to_s.strip, value.to_s.strip ]
        end
        [ Integer(values["t"], exception: false), values["v0-hmac-sha256"] ]
      end

      def secure_compare(left, right)
        return false unless left.to_s.bytesize == right.to_s.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end
    end
  end
end
