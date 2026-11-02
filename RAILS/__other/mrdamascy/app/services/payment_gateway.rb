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

  class << self
    def normalize!(value)
      METHODS.include?(value) ? value : DEFAULT_METHOD
    end

    # Reserve/initiate the payment for the order on its chosen lane.
    def init!(order, method: DEFAULT_METHOD)
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
      case order.payment_method
      when "stripe"
        StripeClient.sync_payment!(order: order)
      else
        VippsClient.sync_payment!(order: order)
      end
    end
  end
end
