# frozen_string_literal: true

class Marketplace::WebhooksController < ActionController::Base
  skip_forgery_protection
  include Shared::WriteThrottle
  self.write_throttle_limit = 300

  def vipps
    body = request.body.read
    return head(:unauthorized) unless verified_vipps?(body)

    payload = JSON.parse(body)
    ref = payload["reference"] || payload.dig("payment", "reference")
    state = payload["name"] || payload["state"] || payload.dig("payment", "state")
    if state.to_s.match?(/AUTHORIZED|CAPTURED|SALE|RESERVED/i)
      payable = Webhooks::PaymentPaid.find_by_payment_reference(ref)
      Webhooks::PaymentPaid.mark_paid!(payable, reference: ref) if payable
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  def dintero_callback
    return head(:bad_request) unless Marketplace::Payments::DinteroSignature.valid_callback?(
      header: request.headers["Dintero-Signature"],
      request: request
    )

    reference = params[:merchant_reference].presence ||
      params.dig(:authorization, :merchant_reference).presence
    transaction_id = params[:transaction_id].presence ||
      params.dig(:authorization, :transaction_id).presence
    error = params[:error].presence || params.dig(:authorization, :error).presence
    status = params[:status].presence || params[:state].presence ||
      (error.present? ? "FAILED" : "AUTHORIZED")

    return head(:bad_request) if reference.blank? || transaction_id.blank?

    process_transaction(
      "merchant_reference" => reference,
      "id" => transaction_id,
      "status" => status
    )
    head :ok
  rescue Marketplace::Payments::ProviderError
    head :bad_gateway
  rescue StandardError => error
    Rails.logger.warn("[dintero] callback: #{error.class}: #{error.message}")
    head :internal_server_error
  end

  def dintero
    body = request.body.read
    return head(:bad_request) unless Marketplace::Payments::DinteroSignature.valid_webhook?(
      header: request.headers["event-signature"],
      body: body
    )

    payload = JSON.parse(body)
    event_delivery = request.headers["event-delivery"].presence || payload["event_delivery"].presence
    event = payload["event"].presence || request.headers["event"].presence
    return head(:bad_request) if event_delivery.blank? || event.blank?
    return head(:bad_request) if payload["event_delivery"].present? && payload["event_delivery"] != event_delivery

    delivery = begin_delivery(event_delivery:, event:)
    return head(:ok) if delivery.succeeded? || delivery.active?

    attempts = 0
    begin
      attempts += 1
      process_event(event, payload)
    rescue StandardError => error
      if attempts < 3
        sleep(attempts == 1 ? 0.25 : 1.0)
        retry
      end

      if delivery.provider_attempts_exhausted?
        delivery.fail!(error)
        return head(:ok)
      end

      delivery.retryable!(error)
      return head(:internal_server_error)
    end

    delivery.finish!
    head :ok
  rescue JSON::ParserError => error
    if defined?(delivery) && delivery
      delivery.fail!(error)
    end
    head :bad_request
  rescue StandardError => error
    Rails.logger.warn("[dintero] webhook: #{error.class}: #{error.message}")
    head :internal_server_error
  end

  private

  def begin_delivery(event_delivery:, event:)
    delivery = Marketplace::WebhookDelivery.find_by(
      provider: "dintero",
      event_delivery: event_delivery
    )
    return delivery if delivery&.succeeded? || delivery&.status == "failed" || delivery&.active?

    if delivery
      delivery.update!(
        status: "processing",
        event: event,
        received_at: Time.current,
        last_error: nil
      )
      return delivery
    end

    Marketplace::WebhookDelivery.create!(
      provider: "dintero",
      event_delivery: event_delivery,
      event: event,
      received_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    Marketplace::WebhookDelivery.find_by!(
      provider: "dintero",
      event_delivery: event_delivery
    )
  end

  def process_event(event, payload)
    case event
    when "checkout_authorization", "checkout_authorization_update"
      process_authorization(payload)
    when "checkout_transaction", "checkout_transaction_update"
      process_transaction(payload["transaction"] || payload)
    when "approval_payout_destination_update"
      process_payout_destination_case(payload["payout_destination_case"] || {})
    when "approval_payout_destination_delete"
      process_payout_destination_case(payload["payout_destination_case"] || {}, deleted: true)
    when "account_payout_destination_add", "account_payout_destination_update", "account_payout_destination_delete"
      process_payout_destination(payload["payout_destination"] || {})
    when "settlement_add"
      true
    else
      true
    end
  end

  def process_authorization(payload)
    authorization = payload["authorization"] || {}
    transaction = payload["transaction"]
    if transaction.is_a?(Hash)
      process_transaction(transaction)
    elsif authorization["error"].present?
      ref = authorization["merchant_reference"]
      payable = Marketplace::Payments::DinteroCheckout.payable_for_reference(ref)
      payable&.fail_payment!(transaction_id: authorization["transaction_id"])
    end
  end

  def process_transaction(transaction)
    return if transaction.blank?

    reference = transaction["merchant_reference"].presence
    transaction_id = transaction["id"].presence || transaction["transaction_id"].presence
    return if reference.blank? || transaction_id.blank?

    payable = Marketplace::Payments::DinteroCheckout.payable_for_reference(reference)
    return unless payable

    case transaction["status"].to_s.upcase
    when "AUTHORIZED"
      payable.authorize_payment!(transaction_id: transaction_id)
    when "CAPTURED"
      Marketplace::Payments::DinteroCheckout.captured!(payable, transaction_id: transaction_id, items: transaction["items"] || [])
    when "FAILED", "VOIDED"
      payable.fail_payment!(transaction_id: transaction_id)
    when "REFUNDED"
      Marketplace::Payments::DinteroCheckout.refunded!(
        payable,
        transaction_id: transaction_id,
        items: transaction["items"] || []
      )
    end
  end

  def process_payout_destination_case(data, deleted: false)
    destination = data["payout_destination_id"].to_s
    return if destination.empty?

    store = Marketplace::Store.find_by(dintero_payout_destination_id: destination)
    return unless store

    store.update!(
      dintero_payout_destination_status: deleted ? "DELETED" : data["case_status"].presence || "UNKNOWN"
    )
  end

  def process_payout_destination(data)
    destination = data["payout_destination_id"].to_s
    return if destination.empty?

    store = Marketplace::Store.find_by(dintero_payout_destination_id: destination)
    return unless store

    store.update!(
      dintero_payout_destination_status: data["case_status"].presence ||
        data["status"].presence || data["state"].presence || "UNKNOWN"
    )
  end

  def verified_vipps?(payload)
    secret = ENV["VIPPS_WEBHOOK_SECRET"].to_s
    return false if secret.empty?

    provided = request.headers["Authorization"].to_s.sub(/\AHMAC\s+/i, "")
    return false if provided.empty?

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, payload))
    ActiveSupport::SecurityUtils.secure_compare(expected, provided)
  end
end
