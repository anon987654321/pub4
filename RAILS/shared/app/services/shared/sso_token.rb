# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module Shared
  # HMAC-signed cross-app SSO payload between MASTER web and RAILS apps.
  # Secret: MASTER_SSO_SECRET (preferred) or MASTER_INTERNAL_TOKEN.
  module SsoToken
    DEFAULT_TTL = 120
    APPS = %w[brgen amber bsdports master].freeze

    module_function

    def secret
      ENV["MASTER_SSO_SECRET"].to_s.strip.presence ||
        ENV["MASTER_INTERNAL_TOKEN"].to_s.strip.presence ||
        ENV["MASTER_BRIDGE_TOKEN"].to_s.strip.presence
    end

    def configured?
      secret.to_s.length >= 16
    end

    def mint(app:, email:, user_id: nil, display_name: nil, ttl: DEFAULT_TTL)
      raise ArgumentError, "SSO secret not configured" unless configured?
      raise ArgumentError, "unknown app #{app}" unless APPS.include?(app.to_s)

      payload = {
        "app" => app.to_s,
        "email" => email.to_s.downcase.strip,
        "user_id" => user_id,
        "display_name" => display_name.to_s.presence,
        "exp" => Time.now.to_i + ttl.to_i,
        "iat" => Time.now.to_i,
        "v" => 1,
      }
      body = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      sig = sign(body)
      "#{body}.#{sig}"
    end

    def verify(token, expected_app: nil)
      return nil unless configured?
      return nil if token.to_s.strip.empty?

      body, sig = token.to_s.split(".", 2)
      return nil if body.blank? || sig.blank?
      return nil unless secure_compare(sign(body), sig)

      payload = JSON.parse(Base64.urlsafe_decode64(body))
      return nil if payload["exp"].to_i < Time.now.to_i
      return nil if expected_app && payload["app"].to_s != expected_app.to_s
      return nil if payload["email"].to_s.strip.empty?

      payload
    rescue JSON::ParserError, ArgumentError
      nil
    end

    def sign(body)
      OpenSSL::HMAC.hexdigest("SHA256", secret, body)
    end

    def secure_compare(a, b)
      return false if a.bytesize != b.bytesize

      ActiveSupport::SecurityUtils.secure_compare(a, b)
    rescue StandardError
      false
    end
  end
end
