# frozen_string_literal: true

require "json"

module Webhooks
  # Stripe Checkout webhooks.
  #
  # Dashboard → Developers → Webhooks:
  #   URL:  https://<host>/webhooks/stripe
  #   Events: checkout.session.completed,
  #           checkout.session.async_payment_succeeded,
  #           customer.subscription.created, .updated, .deleted
  #   Signing secret → STRIPE_WEBHOOK_SECRET (whsec_…)
  #
  # Important: verify against the raw request body bytes, not a re-serialized JSON object.
  #
  # The one Stripe handler. The marketplace engine routes its own
  # /webhooks/stripe here too, because an endpoint registered on
  # markedsplass.<city> before the two were merged still has to be paid.
  class StripeController < ActionController::Base
    skip_forgery_protection
    include Shared::WriteThrottle
    # A payment provider retries in bursts from a handful of addresses.
    self.write_throttle_limit = 300

    def create
      event = Shared::StripeSignature.verify!(request.raw_post, request.headers["Stripe-Signature"].to_s)

      handle_event(event)
      head :ok
    rescue Shared::StripeSignature::Error => e
      Rails.logger.warn("[webhooks/stripe] signature: #{e.message}")
      head :unauthorized
    rescue JSON::ParserError
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("[webhooks/stripe] #{e.class}: #{e.message}")
      head :unprocessable_entity
    end

    private

    # Subscription events (plans in __shared/config/plans.yml) go to billing; the
    # rest are marketplace payments.
    def handle_event(event)
      return if Shared::StripeBilling.handle(event)

      type = event["type"].to_s
      data = event.dig("data", "object") || {}

      case type
      when "checkout.session.completed", "checkout.session.async_payment_succeeded"
        handle_checkout_completed(data)
      when "payment_intent.succeeded"
        handle_payment_intent_succeeded(data)
      else
        Rails.logger.info("[webhooks/stripe] ignored type=#{type}")
      end
    end

    def handle_checkout_completed(session)
      return unless session["payment_status"].to_s.in?(%w[paid no_payment_required])

      order = Webhooks::PaymentPaid.find_order_from_stripe_session(session)
      return if order.nil?

      Webhooks::PaymentPaid.mark_paid!(order, reference: session["id"].to_s)
      gclid = session.dig("metadata", "gclid")
      Webhooks::PaymentPaid.attach_gclid!(order, gclid) if gclid.present?
      Webhooks::PaymentPaid.enqueue_google_conversion(order)
    end

    def handle_payment_intent_succeeded(intent)
      order_id = intent.dig("metadata", "order_id")
      return if order_id.blank?

      order = Webhooks::PaymentPaid.find_order_by_id(order_id)
      return if order.nil?

      Webhooks::PaymentPaid.mark_paid!(order, reference: intent["id"].to_s)
      Webhooks::PaymentPaid.enqueue_google_conversion(order)
    end
  end
end
