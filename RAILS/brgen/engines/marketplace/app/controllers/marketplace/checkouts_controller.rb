# frozen_string_literal: true

class Marketplace::CheckoutsController < Marketplace::BaseController
  before_action :require_user_session

  # What can go wrong between us and a PSP: the provider refusing, the network
  # failing, or a reply missing what we asked for. Anything else is a defect
  # here and raises.
  PAYMENT_ERRORS = [
    Marketplace::Payments::ProviderError,
    Marketplace::Payments::DinteroClient::Error,
    Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, JSON::ParserError, KeyError
  ].freeze

  # The only hosts a checkout may send a buyer to. The URL comes back from the
  # provider's API, and an open redirect would hand a buyer mid-payment to
  # whatever that reply named.
  PROVIDER_HOSTS = {
    "stripe" => %w[checkout.stripe.com],
    "vipps" => %w[vipps.no],
    "dintero" => %w[checkout.dintero.com checkout.api.dintero.com]
  }.freeze

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

    # Credentials-first is LANE-SCOPED. The one-click lane below CREATES an
    # order, and checking the provider afterwards left order debris behind
    # every unconfigured click — caught by that lane's own test. The cart
    # lanes keep the original order (four tests pin it): an empty cart is
    # reported before anything about payment providers, because "nothing to
    # pay" is the buyer's answer and "unconfigured" is the operator's.
    if params[:listing_id].present? && !provider_configured?(provider)
      raise Marketplace::Payments::NotConfigured, provider.capitalize
    end

    payable = resolve_payable
    return if performed?
    unless payable
      redirect_to cart_path, alert: t("flash.marketplace.cart_not_payable")
      return
    end

    # The cart lanes' provider check sits here — after empty-cart, before the
    # address gate — so an unconfigured PSP still fails closed with its reason
    # instead of sending the buyer to the address form for a payment that
    # could never start.
    raise Marketplace::Payments::NotConfigured, provider.capitalize unless provider_configured?(provider)

    Marketplace::Payments::DinteroCheckout.ensure_sellers_ready!(payable) if provider == "dintero" && payable.is_a?(Array)
    Marketplace::Payments::DinteroCheckout.ensure_sellers_ready!([ payable ]) if provider == "dintero" && !payable.is_a?(Array)

    payable = build_basket(payable) if payable.is_a?(Array)
    # build_basket redirects on its own when there is no delivery address —
    # without this guard that became a second redirect and a
    # DoubleRenderError, which is a 500 for a customer who had not
    # saved an address yet.
    return if performed? || payable.nil?

    url = start_payment(provider, payable)
    return if url.nil? || performed?

    unless provider_url?(provider, url)
      Rails.logger.error("[checkout] #{provider} returned a redirect off its own hosts: #{url}")
      redirect_to cart_path, alert: t("marketplace.checkout_errors.provider_failed", provider: provider_name(provider))
      return
    end

    redirect_to url, allow_other_host: true
  rescue Marketplace::Payments::DinteroCheckout::SellerNotReady
    target = params[:listing_id].present? ? listing_path(params[:listing_id]) : cart_path
    redirect_to target, alert: t("flash.marketplace.dintero_seller_not_ready")
  rescue Marketplace::Payments::NotConfigured
    redirect_to cart_path, alert: t("marketplace.checkout_errors.not_configured", provider: provider_name(provider))
  # The buyer is told which provider failed and that nothing was charged. The
  # provider's own words go to the log: they name API fields and account
  # states, not anything a buyer can act on.
  rescue *PAYMENT_ERRORS => e
    Ground::Swallow.log(e, context: "Marketplace::CheckoutsController#create") if defined?(Ground::Swallow)
    redirect_to cart_path, alert: t("marketplace.checkout_errors.provider_failed", provider: provider_name(provider))
  end

  # GET return from PSP. The webhook remains the source of truth for payment —
  # a browser coming back from a redirect proves the customer returned, not that
  # any money moved.
  def show
    if params[:checkout_id].present?
      checkout = Current.user.marketplace_checkouts.find_by(id: params[:checkout_id])
      redirect_to(cart_path,
                  notice: t("flash.marketplace.payment_recorded",
                            status: t("flash.marketplace.payment_statuses.#{checkout&.status || 'open'}"),
                            provider: checkout&.payment_provider || params[:provider]))
      return
    end

    order = Current.user.marketplace_orders.find_by(id: params[:order_id])
    if order && params[:provider].present? && order.payment_status.in?(%w[pending authorized paid failed refunded])
      redirect_to order_path(order),
                  notice: t("flash.marketplace.payment_recorded",
                            status: t("flash.marketplace.payment_statuses.#{order.payment_status}"),
                            provider: order.payment_provider || params[:provider])
    else
      redirect_to cart_path
    end
  end

  private

  # Three lanes reach payment, and which one is running is decided by the
  # parameter that arrived.
  #
  # listing_id is the ONE-CLICK lane (operator, 2026-08-22): the buy bar posts
  # here directly and the order is created and paid in the same request —
  # listing → Vipps app → done, one click on the site. The single-order path it
  # joins has no address gate on purpose: classifieds delivery is negotiated
  # between the parties, and Vipps carries the buyer's identity.
  def resolve_payable
    return create_buy_now_order if params[:listing_id].present?
    return find_payable_order if params[:order_id].present?

    payable_orders.presence
  end

  # The buy bar's one-click order: same construction as OrdersController#create
  # (variant-aware price, quantity 1) minus the offer framing — this is a
  # purchase, not a negotiation. The seller still gets the order notification.
  def create_buy_now_order
    listing = Marketplace::Listing.find_by(id: params[:listing_id])
    if listing.nil? || !listing.buyable? || listing.expired? || listing.status != "active"
      redirect_to(listing ? listing_path(listing) : cart_path, alert: t("flash.marketplace.offer_failed"))
      return nil
    end
    if params[:provider].to_s == "dintero" && !Marketplace::Payments::DinteroCheckout.supported_listing?(listing)
      redirect_to listing_path(listing), alert: t("flash.marketplace.dintero_seller_not_ready")
      return nil
    end
    if listing.user_id == Current.user.id
      redirect_to listing_path(listing), alert: t("flash.marketplace.offer_failed")
      return nil
    end

    variant = listing.variants.find_by(id: params[:variant_id])
    order = listing.orders.create(
      buyer: Current.user,
      variant: variant,
      price_cents: variant&.price_cents_or_listing || listing.price_cents,
      quantity: 1
    )
    unless order.persisted?
      redirect_to listing_path(listing), alert: t("flash.marketplace.offer_failed")
      return nil
    end
    # By id, not listing.user: the listing arrives bare-loaded and
    # strict_loading raises on the lazy association — the same trap that hid
    # in ModerationWorkflow#penalize_owner, caught here by this lane's test
    # before it could reach a customer mid-payment.
    seller = User.find_by(id: listing.user_id)
    order.deliver_notification(seller, title: "New marketplace order",
                                       body: "#{Current.user.display_name}: #{listing.title}") if seller
    order.record_activity!("MarketplaceOfferSent", actor: Current.user, source_vertical: "marketplace")
    order
  end

  # The host itself or a subdomain of it, over https. Vipps answers from
  # landing.vipps.no in production and a -mt variant in test.
  def provider_url?(provider, url)
    uri = URI.parse(url.to_s)
    return false unless uri.is_a?(URI::HTTPS) && uri.host.present?

    PROVIDER_HOSTS.fetch(provider, []).any? { |host| uri.host == host || uri.host.end_with?(".#{host}") }
  rescue URI::InvalidURIError
    false
  end

  def provider_name(provider) = t("marketplace.payment_providers.#{provider}")

  def provider_configured?(provider)
    case provider
    when "stripe" then Marketplace::Payments::StripeCheckout.configured?
    when "vipps"  then Marketplace::Payments::VippsCheckout.configured?
    when "dintero" then Marketplace::Payments::DinteroCheckout.configured?
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
    when "dintero"
      Marketplace::Payments::DinteroCheckout.start!(
        order: payable,
        return_url: return_url(payable, "dintero"),
        callback_url: dintero_callback_url
      )
    end
  end

  def dintero_callback_url
    webhooks_dintero_callback_url
  end

  def return_url(payable, provider)
    if payable.is_a?(Marketplace::Checkout)
      checkout_url(provider: provider, checkout_id: payable.id)
    else
      checkout_url(provider: provider, order_id: payable.id)
    end
  end

  def payable_orders
    Current.user.marketplace_orders.includes(:listing).select(&:startable?)
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
    # Must be payable, not merely owned. Without that, POST /checkout?order_id=
    # of a paid/declined row walked into StripeCheckout.start!, which then
    # called mark_payment_pending! and rewound payment_status back to pending.
    order = Current.user.marketplace_orders.includes(:listing).find_by(id: params[:order_id])
    order if order&.startable?
  end
end
