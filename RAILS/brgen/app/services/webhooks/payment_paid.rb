# frozen_string_literal: true

module Webhooks
  # Shared post-payment actions for Stripe + Vipps webhooks.
  module PaymentPaid
    module_function

    # mark_paid! notifies the seller (listing.user) and the buyer and reads the
    # listing title. Every model is strict_loading by default and production
    # raises on a violation, so those associations arrive preloaded.
    def find_order_by_id(id)
      Marketplace::Order.includes(:buyer, listing: :user).find_by(id: id) if defined?(Marketplace::Order)
    end

    def find_checkout_by_id(id)
      Marketplace::Checkout.find_by(id: id) if defined?(Marketplace::Checkout)
    end

    # StripeCheckout stamps the payable twice: client_reference_id as
    # "order_id:N" or "checkout_id:N", and the same id under metadata. A basket
    # and an order share an id sequence only by accident, so the prefix decides
    # which table the number belongs to. A session carrying neither falls back
    # to the session id that mark_payment_pending! stored.
    def find_order_from_stripe_session(session)
      ref = session["client_reference_id"].to_s
      meta = session["metadata"] || {}

      if ref.start_with?("order_id:")
        find_order_by_id(ref.split(":", 2).last)
      elsif ref.start_with?("checkout_id:")
        find_checkout_by_id(ref.split(":", 2).last)
      elsif meta["checkout_id"].present?
        find_checkout_by_id(meta["checkout_id"])
      elsif meta["order_id"].present?
        find_order_by_id(meta["order_id"])
      elsif session["id"].present?
        find_by_payment_reference(session["id"])
      end
    end

    # VippsCheckout stores the exact reference on the order or basket it charged
    # (mark_payment_pending!), so that row is the answer. The id inside the
    # reference is only a fallback, and it names its table: references made
    # before 2026-11-04 said "brgen-order-{id}" for baskets too, so reading that
    # number as an order id paid whichever unrelated order shared the id.
    def find_order_from_vipps_reference(reference)
      stored = find_by_payment_reference(reference)
      return stored if stored

      kind, id = reference.to_s.match(/\Abrgen-(order|checkout|takeaway)-(\d+)-/)&.captures
      case kind
      when "checkout" then find_checkout_by_id(id)
      when "takeaway" then find_takeaway_order_by_id(id)
      when "order" then find_order_by_id(id)
      end
    end

    # A takeaway order paid with Vipps. mark_paid! notifies the kitchen, so the
    # restaurant arrives with it.
    def find_takeaway_order_by_id(id)
      Takeaway::Order.includes(:restaurant).find_by(id: id) if defined?(Takeaway::Order)
    end

    # A basket and its lines share one payment_reference, so the basket is asked
    # first: finding a line first pays one seller and leaves the basket open.
    def find_by_payment_reference(reference)
      return if reference.blank? || !defined?(Marketplace::Order)

      Marketplace::Checkout.find_by(payment_reference: reference) ||
        Marketplace::Order.includes(:buyer, listing: :user).find_by(payment_reference: reference) ||
        (Takeaway::Order.includes(:restaurant).find_by(payment_reference: reference) if defined?(Takeaway::Order))
    end

    # Only a payable order or basket moves to paid, so a replayed or late event
    # cannot reopen a refunded or cancelled one. The models guard the transition
    # itself inside their own transaction.
    #
    # Out of stock is answered, not raised: the buyer paid for the last one after
    # someone else did, the webhook has nothing to retry, and a 4xx or 5xx would
    # have Stripe redeliver it for three days.
    def mark_paid!(payable, reference:)
      return payable unless payable.payable?

      payable.mark_paid!(reference: reference)
      payable
    rescue RuntimeError => e
      raise unless e.message.include?("not in stock")

      Rails.logger.warn("[webhooks] #{payable.class.name}##{payable.id} paid while out of stock")
      payable
    end

    def attach_gclid!(order, gclid)
      return if gclid.blank?
      return unless order.respond_to?(:gclid)

      order.update_column(:gclid, gclid) if order.gclid.blank?
    end

    def enqueue_google_conversion(order)
      return unless defined?(GoogleEnhancedConversionsJob)
      return unless defined?(GoogleEnhancedConversions) && GoogleEnhancedConversions.configured?

      GoogleEnhancedConversionsJob.perform_later(order.id)
    end
  end
end
