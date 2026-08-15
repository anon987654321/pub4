# frozen_string_literal: true

class Marketplace::WebhooksController < ActionController::Base
  # Standalone — no session; PSP webhooks only.
  skip_forgery_protection

  # Reject events whose signed timestamp is further than this from now, so a
  # captured request cannot be replayed indefinitely.
  SIGNATURE_TOLERANCE = 5.minutes

  # Both handlers FAIL CLOSED. Previously stripe only checked that a
  # Stripe-Signature header was non-blank (and only when the secret happened to
  # be set), and vipps checked nothing at all — so an unauthenticated POST could
  # mark any order paid. Order ids are sequential, and these routes are public
  # with skip_forgery_protection and no rate limit.
  def stripe
    payload = request.body.read
    return head(:unauthorized) unless verified_stripe?(payload)

    event = JSON.parse(payload)
    if event["type"] == "checkout.session.completed"
      obj = event.dig("data", "object") || {}
      ref = obj["id"]
      meta = obj["metadata"] || {}
      # Basket sessions stamp checkout_id. Looking that number up on Order
      # used to mark a colliding sequential Order paid and leave the basket open.
      if meta["checkout_id"].present?
        mark_paid_checkout(Marketplace::Checkout.find_by(id: meta["checkout_id"]), ref)
      else
        order_id = meta["order_id"].presence || obj["client_reference_id"].to_s.delete_prefix("order_id:")
        order = payable_scope.find_by(id: order_id) || payable_scope.find_by(payment_reference: ref)
        mark_paid(order, ref)
      end
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  def vipps
    body = request.body.read
    return head(:unauthorized) unless verified_vipps?(body)

    payload = JSON.parse(body)
    ref = payload["reference"] || payload.dig("payment", "reference")
    order = payable_scope.find_by(payment_reference: ref)
    state = payload["name"] || payload["state"] || payload.dig("payment", "state")
    mark_paid(order, ref) if state.to_s.match?(/AUTHORIZED|CAPTURED|SALE|RESERVED/i)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  # mark_paid! notifies both the seller (listing.user) and the buyer, and reads
  # the listing title. Every model here is strict_loading by default (shared
  # ApplicationRecord) and production raises on a violation, so the associations
  # that path touches are preloaded rather than walked lazily. Marketplace::Order
  # also guards each of those reads itself — this just avoids the extra queries.
  def payable_scope
    Marketplace::Order.includes(:buyer, listing: :user)
  end

  # Only transition orders that are actually awaiting payment, so a replayed or
  # duplicated event cannot re-open a refunded or cancelled order.
  def mark_paid(order, reference)
    order&.mark_paid!(reference: reference) if order&.payable?
  end

  def mark_paid_checkout(checkout, reference)
    checkout&.mark_paid!(reference: reference) if checkout&.payable?
  end

  # Stripe's documented scheme: `Stripe-Signature: t=<unix>,v1=<hex hmac>`,
  # HMAC-SHA256 over "<t>.<raw body>" keyed with the endpoint's whsec_ secret.
  # This needs no stripe gem — the previous comment claiming otherwise is why
  # the check was never implemented.
  def verified_stripe?(payload)
    secret = ENV["STRIPE_WEBHOOK_SECRET"].to_s
    return false if secret.empty?

    parts = parse_signature_header(request.headers["Stripe-Signature"])
    timestamp = parts["t"].to_s.to_i
    return false if timestamp.zero? || (Time.current.to_i - timestamp).abs > SIGNATURE_TOLERANCE.to_i

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    # Stripe may send several v1 signatures during key rotation; any match is valid.
    Array(parts["v1"]).any? { |candidate| secure_equal?(expected, candidate) }
  end

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
    secure_equal?(expected, provided)
  end

  def parse_signature_header(header)
    header.to_s.split(",").each_with_object(Hash.new { |h, k| h[k] = [] }) do |pair, acc|
      key, value = pair.strip.split("=", 2)
      next if key.nil? || value.nil?

      acc[key] << value
    end.transform_values { |values| values.size == 1 ? values.first : values }
  end

  def secure_equal?(expected, candidate)
    candidate = candidate.to_s
    return false if candidate.empty?

    ActiveSupport::SecurityUtils.secure_compare(expected, candidate)
  end
end
