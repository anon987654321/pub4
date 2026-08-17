# frozen_string_literal: true

module Webhooks
  # TradeDoubler Conversions API receiver (POST subscription).
  #
  # Configure at TradeDoubler with receiverUrl pointing here and attributes such
  # as ${transactionId}, ${orderNumber}, ${messageTypeId}, ${publisherCommission},
  # ${epi}, ${epi2}, ${orderValue}, ${currencyId}, ${programId}.
  #
  # Auth: shared token in query (?token=) or header X-Tradedoubler-Token matching
  # TRADEDOUBLER_WEBHOOK_SECRET (or CONVERSIONS token). Fail closed when unset.
  class TradedoublerController < ActionController::Base
    skip_forgery_protection

    def create
      return head(:unauthorized) unless authorized?

      payload = request.request_parameters.presence || parse_body
      record = Shared::AffiliateConversion.record_from_postback!(payload)
      return head(:unprocessable_entity) if record.nil?

      head :ok
    rescue ActiveRecord::RecordInvalid, ArgumentError
      head :unprocessable_entity
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def authorized?
      secret = ENV["TRADEDOUBLER_WEBHOOK_SECRET"].presence ||
               ENV["TRADEDOUBLER_CONVERSIONS_TOKEN"].presence
      return false if secret.blank?

      provided = params[:token].presence ||
                 request.headers["X-Tradedoubler-Token"].to_s.presence
      return false if provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(secret, provided)
    end

    def parse_body
      raw = request.body.read
      return ActionController::Parameters.new({}) if raw.blank?

      JSON.parse(raw)
    end
  end
end
