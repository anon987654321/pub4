# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "openssl"

module Webhooks
  # Vipps MobilePay ePayment webhooks (Webhooks API).
  #
  # Register (once) via Vipps API:
  #   POST /webhooks/v1/webhooks
  #   events: epayments.payment.authorized.v1, epayments.payment.captured.v1, …
  #   Store the returned `secret` as VIPPS_WEBHOOK_SECRET (base64 string from Vipps).
  #
  # Auth: HMAC-SHA256 over method + pathAndQuery + "date;host;contentSha256"
  # Headers: x-ms-date, host, x-ms-content-sha256, Authorization
  # See: https://developer.vippsmobilepay.com/docs/APIs/webhooks-api/request-authentication/
  #
  # Payment reference was set at create time (VippsCheckout.start!) as e.g.
  #   brgen-order-{id}-{hex}
  # We resolve the order from that reference.
  class VippsController < ActionController::Base
    TOLERANCE_SECONDS = 300

    skip_forgery_protection

    # Events that mean money is reserved / taken — treat as paid for marketplace.
    PAID_NAMES = %w[AUTHORIZED CAPTURED].freeze

    def create
      payload = request.raw_post
      verify!(payload)

      body = JSON.parse(payload)
      handle_payload(body)
      head :ok
    rescue SignatureError => e
      Rails.logger.warn("[webhooks/vipps] signature: #{e.message}")
      head :unauthorized
    rescue JSON::ParserError
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("[webhooks/vipps] #{e.class}: #{e.message}")
      head :unprocessable_entity
    end

    private

    class SignatureError < StandardError; end

    def verify!(payload)
      secret_b64 = ENV["VIPPS_WEBHOOK_SECRET"].to_s.strip
      raise SignatureError, "VIPPS_WEBHOOK_SECRET missing" if secret_b64.blank?

      date = request.headers["x-ms-date"].to_s
      content_hash_hdr = request.headers["x-ms-content-sha256"].to_s
      auth = request.headers["Authorization"].to_s
      host = request.headers["Host"].presence || request.host
      raise SignatureError, "missing auth headers" if date.blank? || content_hash_hdr.blank? || auth.blank?

      # x-ms-date is inside the signed string, so it cannot be edited without
      # breaking the signature — but a signature stays valid forever unless its
      # age is checked. Without this, one captured request replays indefinitely.
      # Stripe bounds the same window at TOLERANCE_SECONDS.
      begin
        age = (Time.now - Time.httpdate(date)).abs
      rescue ArgumentError
        raise SignatureError, "unparseable x-ms-date"
      end
      raise SignatureError, "timestamp outside tolerance (#{age.round}s)" if age > TOLERANCE_SECONDS

      # 1) Content hash: SHA-256 of raw body → base64
      computed_hash = Base64.strict_encode64(Digest::SHA256.digest(payload))
      unless ActiveSupport::SecurityUtils.secure_compare(computed_hash, content_hash_hdr)
        raise SignatureError, "content hash mismatch"
      end

      # 2) String to sign (LF only)
      path_and_query = request.fullpath # includes query if any
      string_to_sign = "POST\n#{path_and_query}\n#{date};#{host};#{content_hash_hdr}"

      # 3) HMAC-SHA256 with webhook secret (secret is base64 from Vipps registration)
      # Vipps returns this secret base64-encoded at registration, but some
      # setups store it raw. Only strict_decode64 rejects a non-base64 string;
      # decode64 mangles it into plausible-looking bytes instead, so the raw
      # branch never runs and every signature fails with nothing to show why.
      key = begin
        Base64.strict_decode64(secret_b64)
      rescue ArgumentError
        secret_b64
      end

      signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, string_to_sign))
      expected_auth = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=#{signature}"

      unless ActiveSupport::SecurityUtils.secure_compare(expected_auth, auth)
        # Also accept if only the Signature= part matches (header formatting variance)
        got_sig = auth[/Signature=([^&\s]+)/, 1].to_s
        unless got_sig.present? && ActiveSupport::SecurityUtils.secure_compare(signature, got_sig)
          raise SignatureError, "authorization signature mismatch"
        end
      end
    end

    def handle_payload(body)
      name = body["name"].to_s.upcase
      success = body["success"] == true
      reference = body["reference"].to_s
      return unless success
      return unless PAID_NAMES.include?(name)
      return if reference.blank?

      order = Webhooks::PaymentPaid.find_order_from_vipps_reference(reference)
      return if order.nil?

      Webhooks::PaymentPaid.mark_paid!(
        order,
        provider: "vipps",
        reference: reference
      )
      Webhooks::PaymentPaid.enqueue_google_conversion(order)
    end
  end
end
