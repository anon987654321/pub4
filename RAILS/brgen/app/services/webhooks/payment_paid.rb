# frozen_string_literal: true

module Webhooks
  # Shared post-payment actions for Stripe + Vipps webhooks.
  module PaymentPaid
    module_function

    def find_order_by_id(id)
      Marketplace::Order.find_by(id: id) if defined?(Marketplace::Order)
    end

    def find_checkout_by_id(id)
      Marketplace::Checkout.find_by(id: id) if defined?(Marketplace::Checkout)
    end

    def find_order_from_stripe_session(session)
      ref = session["client_reference_id"].to_s
      meta = session["metadata"] || {}

      if ref.start_with?("order_id:")
        find_order_by_id(ref.split(":", 2).last)
      elsif ref.start_with?("checkout_id:")
        find_checkout_by_id(ref.split(":", 2).last)
      elsif meta["order_id"].present?
        find_order_by_id(meta["order_id"])
      elsif meta["checkout_id"].present?
        find_checkout_by_id(meta["checkout_id"])
      end
    end

    # VippsCheckout sets reference like "brgen-order-{id}-{hex}"
    def find_order_from_vipps_reference(reference)
      if (m = reference.match(/\Abrgen-order-(\d+)/))
        return find_order_by_id(m[1])
      end

      # Fallback: payment_reference column
      if defined?(Marketplace::Order) && Marketplace::Order.column_names.include?("payment_reference")
        Marketplace::Order.find_by(payment_reference: reference)
      end
    end

    def mark_paid!(order, provider:, reference:)
      # Idempotent: already paid with same or any reference
      if order.respond_to?(:payment_status) && order.payment_status.to_s == "paid"
        return order
      end

      if order.respond_to?(:mark_paid!)
        order.mark_paid!(provider: provider, reference: reference)
      else
        attrs = {}
        attrs[:payment_status] = "paid" if order.respond_to?(:payment_status=)
        attrs[:payment_provider] = provider if order.respond_to?(:payment_provider=)
        attrs[:payment_reference] = reference if order.respond_to?(:payment_reference=)
        attrs[:paid_at] = Time.current if order.respond_to?(:paid_at=)
        order.update!(attrs) if attrs.any?
      end
      order
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
