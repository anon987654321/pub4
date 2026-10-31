# frozen_string_literal: true

require "json"

module Webhooks
  # Stripe subscription events for Amber Premium.
  #
  # Dashboard → Developers → Webhooks:
  #   URL:  https://<amber host>/webhooks/stripe
  #   Events: customer.subscription.created, .updated, .deleted
  #   Signing secret → STRIPE_WEBHOOK_SECRET (whsec_…)
  class StripeController < ActionController::Base
    skip_forgery_protection
    include Shared::WriteThrottle
    # A payment provider retries in bursts from a handful of addresses.
    self.write_throttle_limit = 300

    def create
      event = verified_event
      log_ignored(event) unless Shared::StripeBilling.handle(event)

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

    def verified_event = Shared::StripeSignature.verify!(request.raw_post, request.headers["Stripe-Signature"].to_s)

    def log_ignored(event) = Rails.logger.info("[webhooks/stripe] ignored type=#{event["type"]}")
  end
end
