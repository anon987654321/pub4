# frozen_string_literal: true

class CheckoutController < ApplicationController
  # The min-basket flash formats øre through the same money() rule as the
  # views — one formatter, no controller-side copy.
  include ApplicationHelper
  # Real mode without credentials raises VippsClient::NotAvailable or
  # StripeClient::NotAvailable; the checkout says so honestly instead of
  # 500-ing (payment honesty: no fake success, no half-captured orders — the
  # cart is untouched and the customer can retry).
  rescue_from VippsClient::NotAvailable, StripeClient::NotAvailable,
              with: :payment_unavailable

  # The postcode lookup is debounced as it is typed; a script walking every
  # postcode in Norway is not.
  rate_limit to: 60, within: 1.minute, only: :zone, name: "zone_lookup"

  # The one confirm screen (APP_SPEC §6/§12): prefilled address, mode toggle,
  # Vipps payment row, auto-applied promo line, totals — one "Betal med
  # Vipps" CTA. No promo field, no card fields, no tip step.
  def show
    load_checkout_vars
  end

  def create
    @cart = current_cart
    return redirect_to(cart_path, alert: t("cart.empty")) if @cart.cart_items.empty?

    attrs = checkout_params
    # The confirm form's radios are named `mode` (the cart links here with
    # ?mode= too); reading only delivery_mode turned every pickup into delivery.
    mode = (attrs[:delivery_mode].presence || params[:mode]) == "pickup" ? "pickup" : "delivery"
    address = attrs[:address].presence || current_user&.default_address
    postcode = attrs[:postcode].presence || current_user&.default_postcode
    phone = attrs[:phone].presence || current_user&.phone

    zone = mode == "delivery" ? DeliveryZone.for_postcode(postcode) : nil
    subtotal_ore = @cart.subtotal_ore

    # Zone rule (APP_SPEC §4): postcode must be served and the basket must
    # clear the zone minimum. Pickup skips the zone entirely.
    if mode == "delivery" && zone.nil?
      load_checkout_vars
      flash.now[:alert] = t("flash.zone_error", postcode: postcode.to_s)
      return render :show, status: :unprocessable_entity
    end
    if mode == "delivery" && !zone.covers?(subtotal_ore)
      load_checkout_vars
      flash.now[:alert] = t("flash.min_basket", name: zone.name,
                                                amount: money(zone.min_basket_ore))
      return render :show, status: :unprocessable_entity
    end

    kitchen = Kitchen.first
    return redirect_to(cart_path, alert: t("checkout.closed")) if kitchen.nil?

    order = Order.new(
      user: current_user,
      kitchen: kitchen,
      state: "placed",
      delivery_mode: mode,
      address: address,
      postcode: mode == "delivery" ? postcode : kitchen.postcode,
      phone: phone,
      payment_state: "pending",
      payment_steps: 3,
      express: true
    )

    # Denormalised snapshot: order_items are frozen copies of the cart lines
    # (name, emoji, unit price incl. options, human option list) — one shared
    # implementation on the model, used for both new and persisted orders.
    order.snapshot_from_cart!(@cart)

    promo_result = PromoApplier.call(
      subtotal_ore: subtotal_ore,
      delivery_mode: mode,
      user: current_user,
      delivery_fee_ore: zone&.fee_ore.to_i
    )

    begin
      order.compute_totals!(zone, promo_result)
    rescue ActiveRecord::RecordInvalid
      load_checkout_vars
      flash.now[:alert] = t("checkout.failed")
      return render :show, status: :unprocessable_entity
    end

    # Payment lane: Vipps (default) or Stripe Checkout — the two buttons on
    # the confirm screen each submit their own payment_method value. Unknown
    # values fall back to Vipps (PaymentGateway.normalize!).
    payment_method = PaymentGateway.normalize!(attrs[:payment_method])
    order.payment_method = payment_method

    # init_payment owns the payment state: mock → "authorised" (the mock page
    # approves it next), real → "pending" until the PSP reports paid
    # (the webhook or tracking-poll sync then captures). One seam, no double
    # truth.
    begin
      PaymentGateway.init!(order, method: payment_method)
      order.save!
    rescue VippsClient::NotAvailable, StripeClient::NotAvailable
      # No payment was reserved — never leave a zombie on the kitchen board.
      # The cart is untouched, so the customer just retries (payment honesty).
      order.cancel! if order.persisted? && order.state == "placed"
      raise
    end
    @cart.empty!

    redirect_to(order.vipps_url.presence || track_path(order.tracking_token),
                allow_other_host: true, status: :see_other)
  end

  # Zone feedback for the zone_check Stimulus controller while the postcode
  # is typed (APP_SPEC §8): JSON {ok, fee_ore, eta, name}.
  def zone
    if (z = DeliveryZone.for_postcode(params[:postcode]))
      render json: { ok: true, fee_ore: z.fee_ore, eta: z.eta_minutes, name: z.name }
    else
      render json: { ok: false, fee_ore: nil, eta: nil, name: nil }
    end
  end

  private

  # Honest payment failure: nothing was reserved, the cart is intact, retry
  # works. Never a fake success and never a raw 500.
  def payment_unavailable
    load_checkout_vars
    flash.now[:alert] = t("checkout.payment_unavailable")
    render :show, status: :service_unavailable
  end

  # Accepts both the form_with model shape (params[:order][…]) and plain
  # field names, so the confirm form stays free to pick either. The payment
  # method rides plain params (each pay button submits its own value).
  def checkout_params
    source = params[:order].is_a?(ActionController::Parameters) ? params.require(:order) : params
    source.permit(:address, :postcode, :phone, :delivery_mode, :payment_method)
  end

  # Shared between show and the zone-failure re-render. The mode toggle on the
  # cart page links here with ?mode=, so the picked mode wins over the cart's.
  def load_checkout_vars
    @cart = current_cart
    @lines = @cart.cart_items.includes(:menu_item).order(:id)
    @mode = params[:mode].presence || @cart.delivery_mode || "delivery"
    @order = Order.new(
      address: current_user&.default_address,
      postcode: current_user&.default_postcode,
      phone: current_user&.phone,
      delivery_mode: @mode
    )
    @returning_customer = current_user.present? && current_user.orders.exists?
    @zone = @mode == "pickup" ? nil : DeliveryZone.for_postcode(params[:postcode].presence || current_user&.default_postcode)
    @subtotal_ore = @cart.subtotal_ore
    @promo = PromoApplier.call(
      subtotal_ore: @subtotal_ore,
      delivery_mode: @mode,
      user: current_user,
      delivery_fee_ore: @zone&.fee_ore.to_i
    )
    @delivery_fee_ore = @mode == "pickup" ? 0 : @promo[:delivery_fee_ore]
    @discount_ore = @promo[:discount_ore]
    @total_ore = @subtotal_ore - @discount_ore + @delivery_fee_ore
    @eta_minutes = @mode == "pickup" ? nil : @zone&.eta_minutes
  end
end
