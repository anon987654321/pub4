# frozen_string_literal: true

# Projection of a curated marketplace listing into Google Merchant Center.
# Source of truth remains the listing; this row tracks push state and Google status.
class MerchantOffer < ApplicationRecord
  STATUSES = %w[pending approved disapproved excluded].freeze

  belongs_to :listing, polymorphic: true, optional: true
  # Prefer a concrete association if your app has Marketplace::Listing / Product:
  # belongs_to :listing, class_name: "Marketplace::Listing", optional: true

  validates :offer_id, presence: true, uniqueness: true, length: { maximum: 50 }
  validates :google_status, inclusion: { in: STATUSES }, allow_nil: true

  scope :curated, -> { where(curated: true) }
  scope :pushable, -> { curated.where.not(google_status: "excluded") }

  def self.upsert_for_listing!(listing, attributes = {})
    offer_id = attributes[:offer_id].presence || "brgen-#{listing.id}"
    record = find_or_initialize_by(offer_id: offer_id)
    record.listing = listing if record.respond_to?(:listing=)
    record.assign_attributes(
      content_language: attributes[:content_language] || ENV.fetch("GOOGLE_MERCHANT_CONTENT_LANGUAGE", "nb"),
      feed_label: attributes[:feed_label] || ENV.fetch("GOOGLE_MERCHANT_FEED_LABEL", "NO"),
      curated: attributes.fetch(:curated, true),
      gtin: attributes[:gtin],
      brand: attributes[:brand],
      condition: attributes[:condition],
      last_error: nil
    )
    record.save!
    record
  end

  def mark_pushed!
    update!(last_pushed_at: Time.current, last_error: nil)
  end

  def mark_error!(message)
    update!(last_error: message.to_s.truncate(500))
  end
end
