# frozen_string_literal: true

# A TradeDoubler (or other network) conversion postback.
#
# message_type_id follows TradeDoubler Conversions API:
#   1 Tracked, 2 Invalid, 3 Paused, 4 Pending, 5 Tracked_Approved,
#   6 Pending_Approved, 7 Paused_Deleted, 8 Deleted, 9 Paid
module Shared
  class AffiliateConversion < ApplicationRecord
    # Namespaced into Shared when the affiliate stack moved out of brgen so
    # amber could use it too. The table is not: it predates the move and both
    # apps migrate it under its own name.
    self.table_name = "affiliate_conversions"

    SOURCES = %w[tradedoubler].freeze
    PARAMETER_KEYS = {
      legacy_transaction_id: %i[legacyTransactionId],
      order_number: %i[orderNumber order_number],
      message_type_id: %i[messageTypeId message_type_id],
      event_type_id: %i[eventTypeId event_type_id],
      program_id: %i[programId program_id],
      site_id: %i[siteId site_id],
      site_name: %i[siteName site_name],
      order_value: %i[orderValue order_value],
      publisher_commission: %i[publisherCommission publisher_commission],
      currency: %i[currencyId currency],
      product_id: %i[productId product_id],
      product_name: %i[productName product_name],
      epi: %i[epi],
      epi2: %i[epi2],
      visitor_id: %i[visitorId visitor_id],
      sequence_number: %i[sequenceNumber sequence_number],
      time_of_event: %i[timeOfEvent time_of_event],
      time_of_visit: %i[timeOfVisit time_of_visit],
    }.freeze
    INTEGER_FIELDS = %i[event_type_id program_id site_id].freeze
    TIME_FIELDS = %i[time_of_event time_of_visit].freeze

    MESSAGE_TYPES = {
      1 => "tracked",
      2 => "invalid",
      3 => "paused",
      4 => "pending",
      5 => "tracked_approved",
      6 => "pending_approved",
      7 => "paused_deleted",
      8 => "deleted",
      9 => "paid",
    }.freeze

    validates :source, inclusion: { in: SOURCES }
    validates :message_type_id, presence: true, inclusion: { in: MESSAGE_TYPES.keys }
    validates :transaction_id, uniqueness: { scope: %i[source message_type_id] }, allow_nil: true

    scope :approved, -> { where(message_type_id: [ 5, 6 ]) }
    scope :paid, -> { where(message_type_id: 9) }
    scope :for_epi_prefix, ->(prefix) { where("epi LIKE ?", "#{sanitize_sql_like(prefix)}%") if prefix.present? }

    def status_name = MESSAGE_TYPES[message_type_id] || "unknown"

    def approved? = [ 5, 6 ].include?(message_type_id)
    def paid? = message_type_id == 9

    # Parse EPI segments city:bergen|surface:newsletter_weekly|…
    def epi_parts
      epi.to_s.split("|").each_with_object({}) do |part, acc|
        key, value = part.split(":", 2)
        acc[key] = value if key.present? && value.present?
      end
    end

    def self.record_from_postback!(params, source: "tradedoubler")
      raw = payload_hash(params)
      attrs = normalize_params(raw)
      return nil if attrs[:message_type_id].blank?

      # Without a transaction id, use order+message as a soft key so retries do
      # not explode the table, but still accept first write.
      key = {
        source:,
        transaction_id: attrs[:transaction_id].presence ||
                        "order:#{attrs[:order_number]}:msg:#{attrs[:message_type_id]}",
        message_type_id: attrs[:message_type_id],
      }

      record = find_or_initialize_by(key)
      # The key owns transaction_id. Assigning attrs' own copy wrote nil over the
      # soft key, so the next retry of an id-less postback found nothing and
      # inserted a duplicate paid conversion.
      record.assign_attributes(attrs.except(:message_type_id, :transaction_id).merge(raw_payload: raw))
      record.message_type_id = attrs[:message_type_id]
      record.save!
      record
    end

    def self.payload_hash(params)
      if params.respond_to?(:to_unsafe_h)
        params.to_unsafe_h
      elsif params.is_a?(Hash)
        params
      else
        params.to_h
      end
    end

    def self.normalize_params(params)
      p = payload_hash(params).with_indifferent_access
      values = PARAMETER_KEYS.to_h { |field, keys| [ field, fetch_any(p, *keys) ] }
      values[:transaction_id] = fetch_any(p, :transactionId).presence || fetch_any(p, :transaction_id)
      values[:message_type_id] = values[:message_type_id].to_i.nonzero?
      INTEGER_FIELDS.each { |field| values[field] = values[field].presence&.to_i }
      TIME_FIELDS.each { |field| values[field] = parse_time(values[field]) }
      values
    end

    # Read the first truthy alias just as the original lookup expressions did.
    # Kept inside the model so postbacks and other callers share one lookup rule.
    def self.fetch_any(params, *keys)
      keys.each do |key|
        value = params[key]
        return value if value
      end
      nil
    end

    def self.parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError # scan: intentional — an unparseable upstream timestamp is absent, not fatal
      nil
    end
  end
end
