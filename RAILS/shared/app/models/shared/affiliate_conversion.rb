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
        source: source,
        transaction_id: attrs[:transaction_id].presence ||
                        "order:#{attrs[:order_number]}:msg:#{attrs[:message_type_id]}",
        message_type_id: attrs[:message_type_id],
      }

      record = find_or_initialize_by(key)
      record.assign_attributes(attrs.except(:message_type_id).merge(raw_payload: raw))
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
      {
        transaction_id: p[:transactionId].presence || p[:transaction_id],
        legacy_transaction_id: p[:legacyTransactionId],
        order_number: p[:orderNumber] || p[:order_number],
        message_type_id: (p[:messageTypeId] || p[:message_type_id]).to_i.nonzero?,
        event_type_id: (p[:eventTypeId] || p[:event_type_id]).presence&.to_i,
        program_id: (p[:programId] || p[:program_id]).presence&.to_i,
        site_id: (p[:siteId] || p[:site_id]).presence&.to_i,
        site_name: p[:siteName] || p[:site_name],
        order_value: p[:orderValue] || p[:order_value],
        publisher_commission: p[:publisherCommission] || p[:publisher_commission],
        currency: p[:currencyId] || p[:currency],
        product_id: p[:productId] || p[:product_id],
        product_name: p[:productName] || p[:product_name],
        epi: p[:epi],
        epi2: p[:epi2],
        visitor_id: p[:visitorId] || p[:visitor_id],
        sequence_number: p[:sequenceNumber] || p[:sequence_number],
        time_of_event: parse_time(p[:timeOfEvent] || p[:time_of_event]),
        time_of_visit: parse_time(p[:timeOfVisit] || p[:time_of_visit]),
      }
    end

    def self.parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError
      nil
    end
  end
end
