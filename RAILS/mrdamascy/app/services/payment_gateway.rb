# frozen_string_literal: true

# One dispatch seam for the two payment lanes (Vipps by default, Stripe
# Checkout as the operator-mandated second option). CheckoutController and the
# tracking syncs ask this module instead of case-mapping on payment_method in
# every caller — one place to know which client owns an order's payment.
class PaymentGateway
  # Unknown values fall back to the default lane: orders created before
  # Stripe existed carry payment_method "vipps", and a tampered param must
  # never pick a PSP the checkout did not intend.
  DEFAULT_METHOD = "vipps"
  METHODS = %w[vipps stripe].freeze
  # Captured and failed are where a payment ends (failed covers Vipps
  # ABORTED/EXPIRED/TERMINATED and an expired Stripe session); asking the PSP
  # again only spends a call from every open tracking tab.
  SETTLED = %w[captured failed].freeze

  class << self
    def normalize!(value)
      METHODS.include?(value) ? value : DEFAULT_METHOD
    end

    # Reserve/initiate the payment for the order on its chosen lane. An order
    # that costs nothing (a free wrap picked up, nothing else in the cart)
    # never reaches a PSP: Vipps and Stripe both refuse a 0 kr payment, and
    # charging a minimum would bill a reward the card promised free. It is
    # settled here instead, so the kitchen sees it confirmed at once.
    def init!(order, method: DEFAULT_METHOD)
      return settle_free!(order) unless order.total_ore.to_i.positive?

      case normalize!(method)
      when "stripe"
        StripeClient.init_payment(order: order)
      else
        VippsClient.init_payment(order: order)
      end
    end

    # The reconciliation seam dispatch: webhook and tracking poll both land
    # here, idempotent regardless of lane.
    def sync!(order)
      return order if SETTLED.include?(order.payment_state)

      case order.payment_method
      when "stripe"
        StripeClient.sync_payment!(order: order)
      else
        VippsClient.sync_payment!(order: order)
      end
    end

    private

    # Nothing to take, so nothing to wait for: settled and confirmed, with no
    # payment reference and no redirect URL (the checkout goes on to the
    # tracking page).
    def settle_free!(order)
      order.assign_attributes(payment_state: "captured", vipps_order_id: nil, vipps_url: nil)
      if order.state == "placed"
        order.state = "confirmed"
        order.confirmed_at = Time.current
      end
      order.save!
      true
    end
  end
end
