# frozen_string_literal: true

module Api
  # Stripe subscription events for the law API's keys.
  #
  # Dashboard → Developers → Webhooks:
  #   URL:  https://ai.brgen.no/api/webhooks/stripe
  #   Events: customer.subscription.created, .updated, .deleted
  #   Signing secret → STRIPE_WEBHOOK_SECRET in this app's env file
  class StripeWebhooksController < ActionController::API
    def create
      event = Shared::StripeSignature.verify!(request.raw_post, request.headers["Stripe-Signature"].to_s)
      sync(event)

      head :ok
    rescue Shared::StripeSignature::Error => e
      Rails.logger.warn("[api/webhooks/stripe] signature: #{e.message}")
      head :unauthorized
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def sync(event)
      return unless Shared::StripeBilling::SUBSCRIPTION_EVENTS.include?(event["type"].to_s)

      ApiKey.sync!(event.dig("data", "object") || {})
    end
  end
end
