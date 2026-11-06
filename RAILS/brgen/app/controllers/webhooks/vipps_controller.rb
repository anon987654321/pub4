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
  #   Store the returned `secret` as VIPPS_WEBHOOK_SECRET.
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
    include Shared::WriteThrottle
    self.write_throttle_limit = 300

    # Events that mean money is reserved / taken — treat as paid for marketplace.
    PAID_NAMES = %w[AUTHORIZED CAPTURED].freeze
    # The buyer backed out, or the payment lapsed or was stopped. Ignoring these
    # left the order or basket pending_payment for good, with no way to retry.
    FAILED_NAMES = %w[ABORTED EXPIRED CANCELLED TERMINATED].freeze

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
      secret = ENV["VIPPS_WEBHOOK_SECRET"].to_s.strip
      raise SignatureError, "VIPPS_WEBHOOK_SECRET missing" if secret.blank?

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

      # 3) HMAC-SHA256 with the webhook secret.
      signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, string_to_sign))
      expected_auth = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=#{signature}"

      raise SignatureError, "authorization signature mismatch" unless
        ActiveSupport::SecurityUtils.secure_compare(expected_auth, auth)
    end

    def handle_payload(body)
      name = body["name"].to_s.upcase
      reference = body["reference"].to_s
      return unless body["success"] == true && reference.present?

      payable = Webhooks::PaymentPaid.find_order_from_vipps_reference(reference)
      return if payable.nil?

      if PAID_NAMES.include?(name)
        Webhooks::PaymentPaid.mark_paid!(payable, reference:)
        # The conversion job reads a marketplace order id; food is not one.
        Webhooks::PaymentPaid.enqueue_google_conversion(payable) unless payable.is_a?(Takeaway::Order)
      elsif FAILED_NAMES.include?(name)
        payable.fail_payment!(provider: "vipps")
      end
    end
  end
end
