# frozen_string_literal: true

module Marketplace
  class Deal < ApplicationRecord
    self.table_name = "marketplace_deals"

    # Engine-ize Shared
    tracks_activity created: "MarketplaceDealCreated", updated: "MarketplaceDealUpdated", source_vertical: "marketplace", actor: :listing_owner
    include Shared::Reactable
    include Shared::Notifiable
    belongs_to :listing, class_name: "Marketplace::Listing"

    # marketplace_deals has no city_id — a deal's city is its listing's — so
    # nothing scoped deals to the request's city and every city's sitemap
    # listed every city's deals.
    include TenantedThrough
    tenanted_through :listing

    validates :headline, presence: true, length: { maximum: 160 }
    validates :badge, length: { maximum: 64 }, allow_blank: true
    validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

    scope :active, -> {
      now = Time.current
      where("starts_at IS NULL OR starts_at <= ?", now)
        .where("ends_at IS NULL OR ends_at >= ?", now)
        .order(priority: :desc, created_at: :desc)
    }
    # A deal whose listing has lapsed is still "active" on its own dates, and
    # used to keep a sold-two-months-ago chair on the marketplace front page.
    scope :live, -> { active.joins(:listing).merge(Marketplace::Listing.live) }

    scope :featured, -> { where(featured: true) }

    def active?
      (starts_at.blank? || starts_at <= Time.current) && (ends_at.blank? || ends_at >= Time.current)
    end

    # Used as the tracks_activity actor, so it runs in an after_commit on a deal
    # that a controller loaded by id — `listing&.user` was a lazy read that
    # raised under strict loading. See Shared::StrictSafeAssociations.
    def listing_owner = strict_safe(:listing)&.user

    after_create :alert_matching_saved_searches

    private

    def alert_matching_saved_searches
      listed = strict_safe(:listing) || listing
      return unless listed

      Marketplace::SavedSearch.alerting.includes(:user, :category).find_each do |search|
        next unless search.due_for_alert?
        next unless search.matches_listing?(listed)

        search.deliver_alert!([ listed ], kind: :price_drop)
      rescue StandardError => error
        Rails.logger.error("Deal##{id} saved-search alert: #{error.class}: #{error.message}")
      end
    end
  end
end
