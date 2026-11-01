# frozen_string_literal: true

class OrdersController < ApplicationController
  before_action :set_order, only: [:show]

  def index
    return redirect_to(new_session_path, notice: t("auth.sign_in_first")) unless current_user

    @orders = current_user.orders.recent
  end

  def show
  end

  # Public live tracking by unguessable token (APP_SPEC §6): state timeline,
  # ETA, courier blurb, poll feed, tip chips + review form after delivery.
  # Vipps sync on load: the customer lands here straight from the Vipps app,
  # so this is where "paid" becomes true — no refresh, no extra tap.
  def track
    @order = Order.find_by!(tracking_token: params[:token].to_s)
    VippsClient.sync_payment!(order: @order)
    @review = @order.review || @order.build_review
  end

  # Polled by the track Stimulus controller every 10 s (APP_SPEC §8); also
  # the reconciliation heartbeat when the webhook was missed. Reports the
  # payment state so the page can flip "betaling" → "betalt" live.
  def status
    order = Order.find_by!(tracking_token: params[:token].to_s)
    VippsClient.sync_payment!(order: order)
    order.reload
    render json: { state: order.state, eta: order.eta_minutes,
                   payment_state: order.payment_state,
                   updated_at: order.updated_at&.iso8601 }
  end

  # Tip chips on the tracking page (0/20/40 kr); total bumps live via
  # Order#add_tip! — tips happen after delivery, never in the flow.
  def tip
    order = Order.find_by!(tracking_token: params[:token].to_s)
    amount = tip_ore_param
    order.add_tip!(amount) if amount.positive?

    redirect_to track_path(order.tracking_token), notice: t("orders.thanks")
  end

  private

  def set_order
    return redirect_to(new_session_path, notice: t("auth.sign_in_first")) unless current_user

    @order = current_user.orders.find(params[:id])
  end

  # Accepts øre (tip_ore) or kroner (tip) — the view picks one; sane cap.
  def tip_ore_param
    ore = params[:tip_ore].present? ? params[:tip_ore].to_i : params[:tip].to_i * 100
    ore.clamp(0, 100_000)
  end
end
