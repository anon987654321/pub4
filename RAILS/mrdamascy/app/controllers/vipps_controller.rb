# frozen_string_literal: true

require "securerandom"
require "active_support/security_utils"

# Vipps endpoints (APP_SPEC §5/§6):
#
#   mock    — dev/test stand-in for the Vipps app (mock mode only)
#   approve — mock payment approval → capture → confirm → tracking
#   callback— the REAL webhook receiver. Vipps POSTs payment events here
#             (AUTHORIZED, ABORTED, EXPIRED, …) and carries the webhook
#             secret in the Authorization header. We verify that secret with
#             a constant-time compare, then hand the event to
#             VippsClient.sync_payment! — the same seam the tracking page's
#             poll uses, so both paths converge idempotently on capture.
#   login_mock — dev/test stand-in for "Logg inn med Vipps" (mock mode only)
#
# The webhook is CSRF-exempt (it is a server-to-server call with no session
# cookie) and authenticated by the webhook secret instead. Replays are fine:
# sync_payment! only moves states forward and capture is idempotent.
class VippsController < ApplicationController
  # Rails' own parameter parser raises before #callback runs when the
  # webhook body is not JSON; answer the documented 400 there too.
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    head :bad_request
  end
  skip_before_action :verify_authenticity_token, only: [ :callback ]

  before_action :refuse_in_real_mode, only: [ :mock, :approve, :login_mock ]

  def mock
    @order = Order.find_by!(tracking_token: params[:token].to_s)
  end

  # Idempotent: re-approving an already captured order just re-lands on track.
  # The kitchen may already have advanced a pending order — capture confirms
  # payment, it never rewinds the kitchen's state.
  def approve
    order = Order.find_by!(tracking_token: params[:token].to_s)

    unless order.payment_state == "captured"
      attrs = { payment_state: "captured" }
      attrs[:state] = "confirmed" if order.state == "placed"
      order.update!(attrs)
    end

    redirect_to track_path(order.tracking_token), notice: t("orders.thanks")
  end

  # Vipps webhook: POST /vipps/callback. Body is a JSON array of payment
  # events: [{ "reference": "mrdamascy-<token>", "state": "AUTHORIZED", … }].
  # Always 200 once verified (Vipps retries non-2xx), 401 on a bad secret,
  # 400 on garbage — and never leaks which part failed beyond the status.
  def callback
    unless webhook_secret_valid?
      head :unauthorized
      return
    end

    events = JSON.parse(request.body.read.to_s)
    events = [ events ] if events.is_a?(Hash)
    Array(events).each do |event|
      order = Order.find_by(vipps_order_id: event["reference"].to_s)
      next if order.nil?

      # state from the wire is the truth; sync_payment! maps it onto our
      # payment_state/order state and captures when Vipps says AUTHORIZED.
      VippsClient.sync_payment!(order: order)
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  # Mock "Logg inn med Vipps" — the dev stand-in for Vipps' own consent
  # screen. Posts phone + name to the session callback as a fake code, so the
  # whole login → prefilled checkout loop runs with zero credentials.
  def login_mock
    @state = params[:state].to_s
    @redirect_to = params[:to].to_s
  end

  private

  # The mock pages ARE the payment/login in mock mode; in real mode they must
  # not answer. Otherwise POST /vipps/mock/approve captures an order no PSP
  # ever reserved. head :not_found halts the action chain — a raised
  # RecordNotFound would be caught by the application-wide rescue and
  # redirect instead of 404-ing.
  def refuse_in_real_mode
    head :not_found unless VippsClient.mock_mode?
  end

  # Vipps webhooks carry the shared webhook secret in the Authorization
  # header (no "Bearer" prefix). Constant-time compare, both sides present.
  def webhook_secret_valid?
    provided = request.headers["Authorization"].to_s
    secret = ENV["VIPPS_WEBHOOK_SECRET"].to_s
    secret.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)
  end
end
