# frozen_string_literal: true

require "json"
require "openssl"

module Webhooks
  # Stripe Checkout webhooks.
  #
  # Dashboard → Developers → Webhooks:
  #   URL:  https://<host>/webhooks/stripe
  #   Events: checkout.session.completed,
  #           checkout.session.async_payment_succeeded
  #   Signing secret → STRIPE_WEBHOOK_SECRET (whsec_…)
  #
  # Important: verify against the raw request body bytes, not a re-serialized JSON object.
  class StripeController < ActionController::Base
    skip_forgery_protection

    TOLERANCE_SECONDS = 300

    def create
      payload = request.raw_post
      sig_header = request.headers["Stripe-Signature"].to_s

      event = verify_and_parse!(payload, sig_header)
      handle_event(event)
      head :ok
    rescue SignatureError => e
      Rails.logger.warn("[webhooks/stripe] signature: #{e.message}")
      head :unauthorized
    rescue JSON::ParserError
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("[webhooks/stripe] #{e.class}: #{e.message}")
      head :unprocessable_entity
    end

    private

    class SignatureError < StandardError; end

    def verify_and_parse!(payload, sig_header)
      secret = ENV["STRIPE_WEBHOOK_SECRET"].to_s.strip
      raise SignatureError, "STRIPE_WEBHOOK_SECRET missing" if secret.blank?
      raise SignatureError, "Stripe-Signature missing" if sig_header.blank?

      # Stripe-Signature: t=1492774577,v1=...,v1=... (multiple v1 possible during rotation)
      parts = Hash.new { |h, k| h[k] = [] }
      sig_header.split(",").each do |segment|
        key, value = segment.split("=", 2)
        next if key.blank? || value.blank?

        parts[key.strip] << value.strip
      end

      timestamp = parts["t"].first
      signatures = parts["v1"]
      raise SignatureError, "malformed Stripe-Signature" if timestamp.blank? || signatures.blank?

      age = (Time.now.to_i - timestamp.to_i).abs
      raise SignatureError, "timestamp outside tolerance (#{age}s)" if age > TOLERANCE_SECONDS

      signed_payload = "#{timestamp}.#{payload}"
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)

      matched = signatures.any? do |candidate|
        ActiveSupport::SecurityUtils.secure_compare(expected, candidate)
      end
      raise SignatureError, "signature mismatch" unless matched

      JSON.parse(payload)
    end

    def handle_event(event)
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

      Webhooks::PaymentPaid.mark_paid!(
        order,
        provider: "stripe",
        reference: session["id"].to_s
      )
      gclid = session.dig("metadata", "gclid")
      Webhooks::PaymentPaid.attach_gclid!(order, gclid) if gclid.present?
      Webhooks::PaymentPaid.enqueue_google_conversion(order)
    end

    def handle_payment_intent_succeeded(intent)
      order_id = intent.dig("metadata", "order_id")
      return if order_id.blank?

      order = Webhooks::PaymentPaid.find_order_by_id(order_id)
      return if order.nil?

      Webhooks::PaymentPaid.mark_paid!(
        order,
        provider: "stripe",
        reference: intent["id"].to_s
      )
      Webhooks::PaymentPaid.enqueue_google_conversion(order)
    end
  end
end
