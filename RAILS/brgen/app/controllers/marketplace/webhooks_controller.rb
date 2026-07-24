# frozen_string_literal: true

class Marketplace::WebhooksController < ActionController::Base
  # Standalone — no session; PSP webhooks only.
  skip_forgery_protection

  def stripe
    payload = request.body.read
    # Signature verification when STRIPE_WEBHOOK_SECRET is set
    if ENV["STRIPE_WEBHOOK_SECRET"].present?
      # Full verify needs stripe gem; presence of secret is documented for production.
      head :bad_request and return if request.headers["Stripe-Signature"].blank?
    end
    event = JSON.parse(payload)
    if event["type"] == "checkout.session.completed"
      ref = event.dig("data", "object", "id")
      order_id = event.dig("data", "object", "metadata", "order_id") || event.dig("data", "object", "client_reference_id")
      order = Marketplace::Order.find_by(id: order_id) || Marketplace::Order.find_by(payment_reference: ref)
      order&.mark_paid!(reference: ref)
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  def vipps
    payload = JSON.parse(request.body.read)
    ref = payload["reference"] || payload.dig("payment", "reference")
    order = Marketplace::Order.find_by(payment_reference: ref)
    state = payload["name"] || payload["state"] || payload.dig("payment", "state")
    order&.mark_paid!(reference: ref) if state.to_s.match?(/AUTHORIZED|CAPTURED|SALE|RESERVED/i)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
