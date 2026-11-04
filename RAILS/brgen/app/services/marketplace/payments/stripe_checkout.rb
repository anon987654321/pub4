# frozen_string_literal: true

module Marketplace
  module Payments
    # Stripe Checkout Session for cart/order totals.
    # Without STRIPE_SECRET_KEY → NotConfigured (never fakes success).
    class StripeCheckout
      API = "https://api.stripe.com/v1/checkout/sessions"

      def self.configured?
        ENV["STRIPE_SECRET_KEY"].to_s.strip.present?
      end

      # Stripe carries its environment in the key rather than the URL, so there
      # is no test host to default to -- but the failure is the same shape as
      # the one Vipps had: an sk_test_ key on a production box takes a customer
      # through a complete, successful-looking checkout that moves no money, and
      # nothing raises.
      #
      # Unlike an unset key, this one cannot be caught by `configured?`, because
      # a test key IS configured. It is not the right one.
      def self.test_key?
        ENV["STRIPE_SECRET_KEY"].to_s.strip.start_with?("sk_test_")
      end

      def self.production?
        defined?(Rails) && Rails.respond_to?(:env) ? Rails.env.production? : false
      end

      def self.ensure!
        raise NotConfigured, "Stripe" unless configured?
        return unless production? && test_key? && ENV["STRIPE_TEST_MODE"].to_s.strip.empty?

        raise NotConfigured,
              "Stripe (sk_test_ key in production takes payments that move no money; " \
              "set STRIPE_TEST_MODE=1 to allow it deliberately)"
      end

      def self.start!(order:, success_url:, cancel_url:)
        ensure!
        raise ArgumentError, "order is not payable" unless order.respond_to?(:startable?) && order.startable?

        payable_kind = order.is_a?(Marketplace::Checkout) ? "checkout_id" : "order_id"
        data = StripeClient.post(API, session_form(order, payable_kind, success_url:, cancel_url:),
                                 idempotency_key: idempotency_key(order, payable_kind))

        order.mark_payment_pending!(provider: "stripe", reference: data["id"])
        data.fetch("url")
      end

      def self.session_form(order, payable_kind, success_url:, cancel_url:)
        {
          "mode" => "payment",
          "success_url" => success_url,
          "cancel_url" => cancel_url,

          "line_items[0][price_data][currency]" => order.payment_currency.downcase,
          "line_items[0][price_data][product_data][name]" => order.payment_description.to_s.truncate(120),
          "line_items[0][price_data][unit_amount]" => order.total_cents.to_i,
          "line_items[0][quantity]" => 1,
          "client_reference_id" => "#{payable_kind}:#{order.id}",

          # Stripe auto-detects from the browser, which put a Norwegian buyer
          # on an English page.
          "locale" => I18n.locale.to_s == "nb" ? "nb" : "en",
          "metadata[#{payable_kind}]" => order.id.to_s,
        }
      end

      # One key per attempt at one total. Keyed on the order alone, a retry after
      # a quantity change or a failed payment sent different params under the
      # old key, and Stripe answered with an idempotency error or the expired
      # session. The previous session id names the attempt: none on the first,
      # and the failed one on each retry after it.
      def self.idempotency_key(order, payable_kind)
        attempt = order.payment_reference.presence || "first"
        "marketplace-checkout-#{payable_kind}-#{order.id}-#{order.total_cents.to_i}-#{attempt}"
      end
    end
  end
end
