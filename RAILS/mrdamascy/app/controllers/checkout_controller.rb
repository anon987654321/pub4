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

  around_action :hold_checkout_claim, only: :create

  # The one confirm screen (APP_SPEC §6/§12): prefilled address, mode toggle,
  # Vipps payment row, auto-applied promo line, totals — one "Betal med
  # Vipps" CTA. No promo field, no card fields, no tip step.
  def show
    remember_mode
    cart = current_cart
    if cart.cart_items.empty?
      placed = cart.unpaid_order_just_placed
      return redirect_to_payment(placed) if placed

      # The cart page renders its own empty state; an alert on top repeated it
      # in the error colour and covered the page heading on a phone.
      return redirect_to(cart_path)
    end

    load_checkout_vars
  end

  def create
    @cart = current_cart
    return redirect_to(cart_path, alert: t("cart.empty")) if @cart.cart_items.empty?

    inputs = checkout_inputs
    zone = inputs[:mode] == "delivery" ? DeliveryZone.for_postcode(inputs[:postcode]) : nil
    return if refused_checkout?(inputs, zone)

    kitchen = Kitchen.first
    return redirect_to(cart_path, alert: t("checkout.closed")) if kitchen.nil?
    return redirect_to(cart_path, alert: closed_text(kitchen)) unless kitchen.open_at?(Time.current)

    # Payment lane: Vipps (default) or Stripe Checkout — the two buttons on
    # the confirm screen each submit their own payment_method value. Unknown
    # values fall back to Vipps (PaymentGateway.normalize!).
    order = build_order(inputs, kitchen:, payment_method: PaymentGateway.normalize!(checkout_params[:payment_method]))
    return unless priced?(order, inputs[:mode], zone)

    pay!(order)
    @cart.empty!
    redirect_to_payment(order)
  end

  # Zone feedback for the zone_check Stimulus controller while the postcode
  # is typed (APP_SPEC §8): JSON {ok, fee_ore, eta, name, min_basket_ore}
  # plus the confirm screen's fee, total and pay-button lines for this cart,
  # worded and formatted here so the page never shows a stale total and the
  # basket minimum is named before the tap.
  def zone
    z = DeliveryZone.for_postcode(params[:postcode])
    quote = checkout_quote(cart: current_cart, mode: "delivery", zone: z)
    render json: zone_answer(z).merge(zone_lines(z, quote))
  end

  private

  def checkout_inputs
    attrs = checkout_params

    # The confirm form's radios are named `mode` (the cart links here with
    # ?mode= too); reading only delivery_mode turned every pickup into delivery.
    { mode: (attrs[:delivery_mode].presence || params[:mode]) == "pickup" ? "pickup" : "delivery",
      address: attrs[:address].presence || current_user&.default_address,
      postcode: attrs[:postcode].presence || current_user&.default_postcode,
      phone: attrs[:phone].presence || current_user&.phone }
  end

  # Renders the refusal and answers true when a rule turns the order back.
  # Each refused field is named beside itself (field_error), not only in the
  # toast. Zone rule (APP_SPEC §4): postcode must be served and the basket
  # must clear the zone minimum. Pickup skips the zone entirely.
  def refused_checkout?(inputs, zone)
    errors = checkout_field_errors(**inputs)
    refused = errors.any? || (inputs[:mode] == "delivery" && delivery_refused?(inputs[:postcode], zone, errors))
    refuse_fields(errors) if refused
    refused
  end

  # An unserved postcode is named beside its field and in the toast; a
  # basket under the zone minimum in the toast. Nil when the zone takes it.
  def delivery_refused?(postcode, zone, errors)
    if zone.nil?
      errors[:postcode] = flash.now[:alert] = t("flash.zone_error", postcode: postcode.to_s)
    elsif !zone.covers?(@cart.subtotal_ore)
      flash.now[:alert] = t("flash.min_basket", name: zone.name, amount: money(zone.min_basket_ore))
    end
  end

  # Denormalised snapshot: order_items are frozen copies of the cart lines
  # (name, emoji, unit price incl. options, human option list) — one shared
  # implementation on the model, used for both new and persisted orders.
  def build_order(inputs, kitchen:, payment_method:)
    delivery = inputs[:mode] == "delivery"
    Order.new(
      user: current_user, kitchen:, state: "placed", delivery_mode: inputs[:mode],
      address: inputs[:address], postcode: delivery ? inputs[:postcode] : kitchen.postcode,
      phone: inputs[:phone], payment_state: "pending", payment_steps: 3, express: true, payment_method:,
      customer_name: checkout_params[:name].presence || current_user&.name,
      delivery_note: (checkout_params[:delivery_note].presence if delivery)
    ).snapshot_from_cart!(@cart)
  end

  def priced?(order, mode, zone)
    promo_result = PromoApplier.call(subtotal_ore: @cart.subtotal_ore, delivery_mode: mode,
                                     user: current_user, delivery_fee_ore: zone&.fee_ore.to_i)
    order.compute_totals!(zone, promo_result)
    true
  rescue ActiveRecord::RecordInvalid
    load_checkout_vars
    flash.now[:alert] = t("checkout.failed")
    render :show, status: :unprocessable_entity
    false
  end

  # init_payment owns the payment state: mock → "authorised" (the mock page
  # approves it next), real → "pending" until the PSP reports paid
  # (the webhook or tracking-poll sync then captures). One seam, no double
  # truth.
  def pay!(order)
    PaymentGateway.init!(order, method: order.payment_method)
    order.save!
  rescue VippsClient::NotAvailable, StripeClient::NotAvailable
    # No payment was reserved — never leave a zombie on the kitchen board.
    # The cart is untouched, so the customer retries (payment honesty).
    order.cancel! if order.persisted?
    raise
  end

  # Idempotent per cart: a repeat post of the confirm form goes on to the
  # order it already placed, and a post while another is still placing the
  # order is turned back instead of building a second one.
  def hold_checkout_claim
    cart = current_cart
    if cart.cart_items.empty?
      placed = cart.unpaid_order_just_placed
      return placed ? redirect_to_payment(placed) : yield
    end
    return redirect_to(cart_path, alert: t("checkout.in_progress")) unless cart.claim_checkout!

    begin
      yield
    ensure
      cart.release_checkout!
    end
  end

  # Delivery needs a street and a four-digit postcode; every order needs a
  # phone the kitchen and courier can call.
  def checkout_field_errors(mode:, address:, postcode:, phone:)
    errors = {}
    if mode == "delivery"
      errors[:address] = t("checkout.errors.address_blank") if address.blank?
      errors[:postcode] = t("checkout.errors.postcode_invalid") unless postcode.to_s.gsub(/\s+/, "").match?(/\A\d{4}\z/)
    end
    errors[:phone] = t("checkout.errors.phone_blank") if phone.blank?
    errors
  end

  def refuse_fields(errors)
    load_checkout_vars
    @field_errors = errors
    render :show, status: :unprocessable_entity
  end

  def redirect_to_payment(order)
    redirect_to(order.vipps_url.presence || track_path(order.tracking_token),
                allow_other_host: true, status: :see_other)
  end

  def zone_answer(zone)
    return { ok: false, fee_ore: nil, eta: nil, name: nil, min_basket_ore: nil } unless zone

    { ok: true, fee_ore: zone.fee_ore, eta: zone.eta_minutes, name: zone.name, min_basket_ore: zone.min_basket_ore }
  end

  def zone_lines(zone, quote)
    total = money(quote[:total_ore])
    unless zone
      return { total_text: total, vipps_label: t("checkout.vipps_cta"), stripe_label: t("checkout.stripe_cta") }
    end

    { fee_text: money(quote[:delivery_fee_ore]), total_text: total,
      eta_text: t("checkout.eta_delivery", eta: zone.eta_minutes),
      minimum_text: minimum_text(zone, quote[:subtotal_ore]),
      vipps_label: t("checkout.vipps_cta_total", total:), stripe_label: t("checkout.stripe_cta_total", total:) }
  end

  # Names what the basket lacks for the zone minimum, or nil once it clears.
  def minimum_text(zone, subtotal_ore)
    short_ore = zone.min_basket_ore.to_i - subtotal_ore
    t("checkout.min_basket_fail", amount: money(short_ore), name: zone.name) if short_ore.positive?
  end

  # Subtotal, promo, delivery fee and total for a cart in a mode and zone —
  # one sum for the confirm screen and the live zone answer.
  def checkout_quote(cart:, mode:, zone:)
    subtotal_ore = cart.subtotal_ore
    promo = PromoApplier.call(subtotal_ore:, delivery_mode: mode, user: current_user,
                              delivery_fee_ore: zone&.fee_ore.to_i)
    delivery_fee_ore = mode == "pickup" ? 0 : promo[:delivery_fee_ore]
    { subtotal_ore:, promo:, delivery_fee_ore:, discount_ore: promo[:discount_ore],
      total_ore: subtotal_ore - promo[:discount_ore] + delivery_fee_ore }
  end

  # The cart's delivery/pickup toggle links here with ?mode=; keeping the
  # choice on the cart lets the toggle show it when the guest goes back.
  def remember_mode
    mode = params[:mode].to_s
    current_cart.update!(delivery_mode: mode) if %w[delivery pickup].include?(mode)
  end

  # Outside the kitchen's hours: when it opens next, today or on a weekday.
  def closed_text(kitchen)
    now = Time.current
    opens = kitchen.next_opening(now)
    return t("checkout.closed_now") unless opens

    time = opens.strftime("%H:%M")
    return t("checkout.opens_today", time:) if opens.to_date == now.to_date

    t("checkout.opens_on", day: t("checkout.weekdays.#{Kitchen::DAYS[opens.wday]}"), time:)
  end

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
    source.permit(:address, :postcode, :phone, :delivery_mode, :payment_method, :name, :delivery_note)
  end

  # A refused post re-renders with what was typed, not the saved defaults.
  def typed_order
    typed = checkout_params.to_h.symbolize_keys.compact_blank
    typed[:customer_name] = typed.delete(:name)
    details = typed.slice(:address, :postcode, :phone, :customer_name, :delivery_note).compact
    Order.new(saved_details.merge(details, delivery_mode: @mode))
  end

  # What the signed-in customer saved, so the confirm screen arrives filled.
  def saved_details
    user = current_user
    { address: user&.default_address, postcode: user&.default_postcode, phone: user&.phone, customer_name: user&.name }
  end

  # Shared between show and the zone-failure re-render. The mode toggle on the
  # cart page links here with ?mode=, so the picked mode wins over the cart's.
  def load_checkout_vars
    @cart = current_cart
    @lines = @cart.cart_items.includes(:menu_item).order(:id)
    @mode = params[:mode].presence || @cart.delivery_mode || "delivery"
    @order = typed_order
    @returning_customer = current_user.present? && current_user.orders.exists?
    @zone = @mode == "pickup" ? nil : DeliveryZone.for_postcode(@order.postcode)
    quote = checkout_quote(cart: @cart, mode: @mode, zone: @zone)
    @subtotal_ore, @promo, @delivery_fee_ore, @discount_ore, @total_ore =
      quote.values_at(:subtotal_ore, :promo, :delivery_fee_ore, :discount_ore, :total_ore)
    @minimum_text = @zone && minimum_text(@zone, @subtotal_ore)
    @eta_minutes = @mode == "pickup" ? nil : @zone&.eta_minutes
    kitchen = current_kitchen
    @closed_text = closed_text(kitchen) if kitchen && !kitchen.open_at?(Time.current)
  end
end
