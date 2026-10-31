# frozen_string_literal: true

require "json"
require "openssl"

module Shared
  # Verifies a Stripe webhook against the raw request body and returns the
  # parsed event. Every app's Stripe endpoint uses this one check.
  #
  # Stripe-Signature: t=1492774577,v1=...,v1=... (several v1 while a secret rotates)
  module StripeSignature
    TOLERANCE_SECONDS = 300

    class Error < StandardError; end

    module_function

    def verify!(payload, header, secret: ENV["STRIPE_WEBHOOK_SECRET"].to_s.strip, now: Time.now.to_i)
      raise Error, "STRIPE_WEBHOOK_SECRET missing" if secret.blank?
      raise Error, "Stripe-Signature missing" if header.blank?

      timestamp, signatures = parse(header)
      age = (now - timestamp.to_i).abs
      raise Error, "timestamp outside tolerance (#{age}s)" if age > TOLERANCE_SECONDS

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
      raise Error, "signature mismatch" unless signatures.any? { |candidate| same?(expected, candidate) }

      JSON.parse(payload)
    end

    def parse(header)
      parts = header.split(",").filter_map { |segment| pair(segment) }
                    .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      parts.default = []
      raise Error, "malformed Stripe-Signature" if parts["t"].empty? || parts["v1"].empty?

      [parts["t"].first, parts["v1"]]
    end

    # ["t", "1492774577"] for one "t=1492774577" segment; nil for a blank half.
    def pair(segment)
      key, value = segment.split("=", 2).map { |half| half.to_s.strip }
      [key, value] if key.present? && value.present?
    end

    def same?(expected, candidate)
      candidate.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, candidate)
    end
  end
end
