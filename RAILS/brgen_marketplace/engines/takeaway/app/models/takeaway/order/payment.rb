# frozen_string_literal: true

class Takeaway::Order
  # Paying for the food in the app, with Vipps. The payable interface is the one
  # Marketplace::Payments::VippsCheckout already speaks (payment_currency,
  # payment_description, total_cents, startable?, mark_payment_pending!), and
  # the webhook pays it through the same guarded mark_paid! a marketplace order
  # has. Paying stays optional: a kitchen still confirms an unpaid order, which
  # is how a diner who pays at the door is served.
  module Payment
    extend ActiveSupport::Concern

    PAYMENT_STATUSES = %w[unpaid pending paid failed refunded].freeze

    included do
      validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
    end

    # The reference prefix VippsCheckout writes: brgen-takeaway-<id>-<hex>. A
    # marketplace order's is brgen-order-<id>, and the two share id numbers only
    # by accident.
    def payment_reference_kind = "takeaway"

    def payment_currency = "NOK"

    def payment_description
      I18n.t("takeaway.payment_description", restaurant: strict_safe_attribute(:restaurant, :name), id: id)
    end

    # A new payment can start on an order the kitchen has not finished with,
    # that has a total, and that is not already paid or with Vipps.
    def startable?
      status.in?(%w[pending confirmed preparing]) && payment_status.in?(%w[unpaid failed]) && total_cents.to_i.positive?
    end

    def payable?
      status != "cancelled" && payment_status.in?(%w[unpaid pending failed])
    end

    def paid? = payment_status == "paid"

    def mark_payment_pending!(provider:, reference:)
      raise "order is not payable" unless payable?

      update!(payment_provider: provider, payment_status: "pending", payment_reference: reference)
    end

    # Paid exactly once: the guard is inside the transaction, so a replayed
    # webhook does not notify the kitchen twice. A paid cart gets a fresh cart
    # deadline, so the stale-cart sweep does not cancel paid food before the
    # kitchen has had time to confirm it.
    def mark_paid!(reference: payment_reference)
      transitioned = false
      transaction do
        lock!
        next if payment_status.in?(%w[paid refunded])

        update!(paid_attributes(reference))
        transitioned = true
      end
      return self unless transitioned

      kitchen = strict_safe(:restaurant)
      deliver_notification(kitchen && User.find_by(id: kitchen.user_id),
                           title: I18n.t("takeaway.payment_received_title", id: id),
                           body: I18n.t("takeaway.payment_received_body", id: id, amount: total_display),
                           source: self, kind: "order")
      self
    end

    # The diner may call off their own order while the kitchen has not
    # confirmed it and no money is with Vipps; after that the restaurant decides.
    def cancellable_by_diner?(user)
      user.present? && user_id == user.id && status == "pending" && payment_status.in?(%w[unpaid failed])
    end

    def fail_payment!(provider: payment_provider, **)
      return self if payment_status.in?(%w[paid refunded])

      update!(payment_status: "failed", payment_provider: provider)
    end

    # A paid order that is cancelled gives the money back. The reservation is
    # released (or the capture refunded) through Vipps; if that fails the order
    # stays paid, so nobody is told a refund happened that did not.
    def refund_cancelled_payment!
      return unless paid? && payment_provider == "vipps"

      Marketplace::Payments::VippsRefund.submit!(order: self, idempotency_key: "brgen-takeaway-#{id}-cancel")
      update!(payment_status: "refunded")
    rescue Marketplace::Payments::NotConfigured, Marketplace::Payments::ProviderError, ArgumentError => error
      Rails.logger.warn("[takeaway] refund held for order #{id}: #{error.class}: #{error.message}")
      nil
    end

    private

    def paid_attributes(reference)
      attrs = { payment_status: "paid", paid_at: Time.current,
                payment_reference: reference.presence || payment_reference }
      attrs[:expires_at] = Takeaway::Order::CART_TTL_MINUTES.minutes.from_now if status == "pending" && expires_at
      attrs
    end
  end
end
