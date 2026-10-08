# frozen_string_literal: true

require "uri"

module Shared
  module Commerce
    PROTOCOL = "pub4-commerce-v1".freeze
    SOURCES = %w[brgen amber].freeze

    Reference = Data.define(:id, :source, :type, :url)
    Candidate = Data.define(
      :id, :title, :description, :merchant, :category, :price_cents, :currency,
      :condition, :availability, :delivery, :trust, :url, :image_url, :reasons, :metadata,
    )

    EVENT_NAMES = %w[
      product_viewed
      product_clicked
      cart_added
      offer_sent
      purchase_completed
      order_shipped
      order_delivered
      return_started
      return_completed,
    ].freeze

    module_function

    def canonical_id(source:, type:, city_id: nil, record_id:)
      parts = [ PROTOCOL, source.to_s, type.to_s, (city_id if city_id.present?), record_id ].compact
      parts.join(":")
    end

    def normalize_query(value)
      value.to_s.downcase.scan(/[[:alnum:]]+/).uniq.first(8)
    end

    def score(value)
      value.to_f.clamp(0.0, 1.0).round(4)
    end

    def reason(code:, text:)
      { code: code.to_s, text: text.to_s }
    end

    def valid_event?(name)
      EVENT_NAMES.include?(name.to_s)
    end

    def amber_handoff_url(base:, title:, category:, source_url:, commerce_key:)
      query = URI.encode_www_form(
        {
          title: title.to_s,
          category: category.to_s.presence,
          source_url: source_url.to_s,
          commerce_key: commerce_key.to_s,
        }.compact,
      )
      "#{base.to_s.sub(%r{/$}, "")}/items/new?#{query}"
    rescue StandardError
      nil
    end
  end
end
