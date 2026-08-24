# frozen_string_literal: true

# A product from an affiliate network (TradeDoubler, Amazon Associates).
#
# Deliberately not city-scoped: an affiliate product belongs to a *market*
# (country), not a city, because that is the granularity affiliate programmes
# are licensed at. `market` is the country code; `for_market` treats a nil
# market as global so a feed that doesn't report one still renders.
module Shared
  class AffiliateProduct < ApplicationRecord
    # Namespaced into Shared when the affiliate stack moved out of brgen so
    # amber could use it too. The table is not: it predates the move and both
    # apps migrate it under its own name.
    self.table_name = "affiliate_products"

    SOURCES = %w[tradedoubler amazon].freeze

    # A feed row older than this is assumed withdrawn. Showing a delisted product
    # is worse than showing none: the click either 404s or pays nothing.
    STALE_AFTER = 7.days

    validates :source, presence: true, inclusion: { in: SOURCES }
    validates :external_id, presence: true, length: { maximum: 128 }
    validates :external_id, uniqueness: { scope: :source }
    validates :title, presence: true, length: { maximum: 300 }
    validates :click_url, presence: true, length: { maximum: 2_000 }
    validates :price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :commission_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :in_stock, -> { where(in_stock: true) }
    scope :fresh, -> { where(last_seen_at: STALE_AFTER.ago..) }
    scope :real, -> { where(placeholder: false) }
    scope :for_market, ->(market) { where(market: [ market.to_s.upcase, nil ]) if market.present? }
    scope :for_category, ->(category) { where(category:) if category.present? }
    # Cheapest-first would reward junk; newest-first at least tracks the feed.
    scope :sellable, -> { in_stock.fresh.order(last_seen_at: :desc) }

    def stale? = last_seen_at.nil? || last_seen_at < STALE_AFTER.ago

    def price
      return nil if price_cents.nil?

      format("%.2f", price_cents / 100.0)
    end

    # Upsert on the network's own id. An importer re-running must not duplicate
    # rows, and must refresh last_seen_at even when nothing else changed —
    # that timestamp is how `fresh` distinguishes live from withdrawn.
    def self.upsert_from_feed!(source:, external_id:, **attributes)
      record = find_or_initialize_by(source:, external_id:)
      record.assign_attributes(attributes)
      record.last_seen_at = Time.current
      record.save!
      record
    end
  end
end
