# frozen_string_literal: true

class Marketplace::CheckoutsController < Marketplace::BaseController
  before_action :require_user_session

  # POST /checkout  provider=stripe|vipps
  #
  # Two shapes, deliberately. order_id pays a single listing — the classifieds
  # case, where an offer to a stranger is negotiated on its own. Without it the
  # whole basket is paid at once: one PSP round trip, one card charge, one
  # delivery address, however many sellers are in it.
  def create
    provider = params[:provider].to_s
    # Validated before any work: assembling a basket and then rejecting the
    # provider would leave a Checkout row behind for a request that could never
    # have been paid, and would answer the wrong page when a buyer has no
    # address saved.
    unless Marketplace::Order::PAYMENT_PROVIDERS.include?(provider)
      redirect_to cart_path, alert: t("flash.marketplace.unknown_provider")
      return
    end

    # The order of these four checks is the order a buyer should meet them in.
    # There is nothing to pay for → say so. The provider has no credentials →
    # say so before asking anyone to type an address. No address → ask for one.
    # Only then is there a basket worth creating.
    payable = params[:order_id].present? ? find_payable_order : payable_orders.presence
    unless payable
      redirect_to cart_path, alert: t("flash.marketplace.cart_not_payable")
      return
    end

    # The services raise this themselves; reaching it here just means a buyer
    # does not fill in a delivery address for a payment that could never start.
    raise Marketplace::Payments::NotConfigured, provider.capitalize unless provider_configured?(provider)

    payable = build_basket(payable) if payable.is_a?(Array)
    # build_basket redirects on its own when there is no delivery address —
    # without this guard that became a second redirect and a
    # DoubleRenderError, which is a 500 for a customer who had simply not
    # saved an address yet.
    return if performed? || payable.nil?

    url = start_payment(provider, payable)
    return if url.nil? || performed?

    redirect_to url, allow_other_host: true
  rescue Marketplace::Payments::NotConfigured => e
    redirect_to cart_path, alert: e.message
  rescue StandardError => e
    Ground::Swallow.log(e, context: "Marketplace::CheckoutsController#create") if defined?(Ground::Swallow)
    redirect_to cart_path, alert: t("flash.marketplace.checkout_failed", message: e.message)
  end

  # GET return from PSP. The webhook remains the source of truth for payment —
  # a browser coming back from a redirect proves the customer returned, not that
  # any money moved.
  def show
    if params[:checkout_id].present?
      checkout = Current.user.marketplace_checkouts.find_by(id: params[:checkout_id])
      redirect_to(checkout ? cart_path : cart_path,
                  notice: t("flash.marketplace.payment_recorded",
                            status: t("flash.marketplace.payment_statuses.#{checkout&.status || 'open'}"),
                            provider: checkout&.payment_provider || params[:provider]))
      return
    end

    order = Current.user.marketplace_orders.find_by(id: params[:order_id])
    if order&.payment_status == "pending" && params[:provider].present?
      redirect_to order_path(order),
                  notice: t("flash.marketplace.payment_recorded",
                            status: t("flash.marketplace.payment_statuses.#{order.payment_status}"),
                            provider: order.payment_provider || params[:provider])
    else
      redirect_to cart_path
    end
  end

  private

  def provider_configured?(provider)
    case provider
    when "stripe" then Marketplace::Payments::StripeCheckout.configured?
    when "vipps"  then Marketplace::Payments::VippsCheckout.configured?
    else false
    end
  end

  def start_payment(provider, payable)
    case provider
    when "stripe"
      Marketplace::Payments::StripeCheckout.start!(
        order: payable, success_url: return_url(payable, "stripe"), cancel_url: cart_url
      )
    when "vipps"
      Marketplace::Payments::VippsCheckout.start!(
        order: payable, return_url: return_url(payable, "vipps")
      )
    end
  end

  def return_url(payable, provider)
    if payable.is_a?(Marketplace::Checkout)
      checkout_url(provider: provider, checkout_id: payable.id)
    else
      checkout_url(provider: provider, order_id: payable.id)
    end
  end

  def payable_orders
    Current.user.marketplace_orders.includes(:listing).select(&:payable?)
  end

  # Everything payable gathered under one Checkout. The address is required: a
  # basket that can be paid without one is a parcel with nowhere to go,
  # discovered after the money has moved.
  def build_basket(orders)
    address = Current.user.marketplace_addresses.default_first.first
    if address.nil?
      redirect_to addresses_path, alert: t("flash.marketplace.address_needed")
      return nil
    end

    checkout = Current.user.marketplace_checkouts.create!(
      marketplace_address: address,
      currency: orders.first.payment_currency
    )
    orders.each { |order| order.update!(marketplace_checkout_id: checkout.id) }
    checkout.recalculate!
    checkout
  end

  def find_payable_order
    Current.user.marketplace_orders.includes(:listing).order(created_at: :desc).find_by(id: params[:order_id])
  end
end
