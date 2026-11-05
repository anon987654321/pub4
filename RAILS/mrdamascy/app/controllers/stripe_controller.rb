# frozen_string_literal: true

require "active_support/security_utils"

# Stripe endpoints — the second payment lane (mirrors VippsController):
#
#   mock     — dev/test stand-in for Stripe's hosted Checkout (mock mode only)
#   approve  — mock payment approval → captured + confirmed → tracking
#   callback — the REAL webhook receiver. Stripe POSTs events here
#              (checkout.session.completed, …) and signs the body; we verify
#              the HMAC signature (Stripe-Signature header) with a constant-
#              time compare, then hand the event to StripeClient.sync_payment!
#              — the same seam the tracking page's poll uses, so both paths
#              converge idempotently on capture.
#
# The webhook is CSRF-exempt (server-to-server, no session cookie) and
# authenticated by the signature instead. Replays are fine: sync_payment! only
# moves states forward and our capture side is idempotent.
class StripeController < ApplicationController
  # Rails' own parameter parser raises before #callback runs when the webhook
  # body is not JSON; answer the documented 400 there too.
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    head :bad_request
  end
  skip_before_action :verify_authenticity_token, only: [ :callback ]

  before_action :refuse_in_real_mode, only: [ :mock, :approve ]

  def mock
    @order = Order.find_by!(tracking_token: params[:token].to_s)
  end

  # Idempotent, same semantics as the Vipps mock approve: re-approving a
  # captured order just re-lands on track; capture confirms payment and never
  # rewinds the kitchen's state.
  def approve
    order = Order.find_by!(tracking_token: params[:token].to_s)
    StripeClient.mark_captured(order)

    redirect_to track_path(order.tracking_token), notice: t("orders.thanks")
  end

  # Stripe webhook: POST /stripe/callback. Body is a JSON event; we care about
  # checkout.session.completed (and let anything else answer 200 so Stripe
  # stops retrying non-relevant events). 400 on a bad signature is NOT used —
  # Stripe retries those, which is what we want for transient issues, but a
  # permanently bad secret would retry forever, so signature failures answer
  # 400 and a missing/unknown session answers 200 (nothing to converge).
  def callback
    # Rack request IO reads once — slurp first, then verify and parse the
    # same buffer (the signature covers the exact bytes Stripe sent).
    payload = request.body.read.to_s

    StripeClient.verify_signature!(
      payload: payload,
      header: request.headers["Stripe-Signature"].to_s,
      secret: ENV["STRIPE_WEBHOOK_SECRET"].to_s
    )

    event = JSON.parse(payload)
    session_object = event.dig("data", "object") || {}
    # Only checkout-session objects carry our reference; anything else
    # (invoices, payouts, …) answers 200 and changes nothing.
    return head :ok unless session_object["object"] == "checkout_session"

    token = session_object["client_reference_id"].to_s
                 .delete_prefix("mrdamascy-").presence ||
             session_object.dig("metadata", "tracking_token").to_s.presence
    order = Order.find_by(tracking_token: token)
    order&.then { |o| StripeClient.sync_payment!(order: o) }
    head :ok
  rescue JSON::ParserError
    head :bad_request
  rescue StripeClient::NotAvailable
    head :bad_request
  end

  private

  # The mock page IS the payment in mock mode; in real mode it must not
  # answer — otherwise POST /stripe/mock/approve captures an order no PSP
  # ever reserved. head :not_found halts the chain (a raised RecordNotFound
  # would be rescued application-wide instead of 404-ing).
  def refuse_in_real_mode
    head :not_found unless StripeClient.mock_mode?
  end
end
