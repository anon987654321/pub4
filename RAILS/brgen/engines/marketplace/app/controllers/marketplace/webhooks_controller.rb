# frozen_string_literal: true

# Vipps callbacks on the marketplace host. Stripe has no action here: the engine
# routes webhooks/stripe to the host's Webhooks::StripeController, the one
# Stripe handler.
class Marketplace::WebhooksController < ActionController::Base
  # Standalone — no session; PSP webhooks only.
  skip_forgery_protection
  include Shared::WriteThrottle
  # A payment provider retries in bursts from a handful of addresses.
  self.write_throttle_limit = 300

  # FAILS CLOSED: an unverified POST marks nothing paid. Order ids are
  # sequential and this route is public with skip_forgery_protection, so the
  # signature is the only thing standing between a guess and a paid order.
  def vipps
    body = request.body.read
    return head(:unauthorized) unless verified_vipps?(body)

    payload = JSON.parse(body)
    ref = payload["reference"] || payload.dig("payment", "reference")
    state = payload["name"] || payload["state"] || payload.dig("payment", "state")
    if state.to_s.match?(/AUTHORIZED|CAPTURED|SALE|RESERVED/i)
      payable = Webhooks::PaymentPaid.find_by_payment_reference(ref)
      Webhooks::PaymentPaid.mark_paid!(payable, reference: ref) if payable
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  # NOTE: confirm against the current Vipps MobilePay webhook docs before
  # enabling in production — the header name and signed string differ between
  # their API generations. Until VIPPS_WEBHOOK_SECRET is set this rejects
  # everything, which is the safe default and strictly better than the previous
  # unconditional trust.
  def verified_vipps?(payload)
    secret = ENV["VIPPS_WEBHOOK_SECRET"].to_s
    return false if secret.empty?

    provided = request.headers["Authorization"].to_s.sub(/\AHMAC\s+/i, "")
    return false if provided.empty?

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, payload))
    ActiveSupport::SecurityUtils.secure_compare(expected, provided)
  end
end
