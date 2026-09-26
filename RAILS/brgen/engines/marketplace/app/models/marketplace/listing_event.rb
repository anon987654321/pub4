# frozen_string_literal: true

class Marketplace::ListingEvent < ApplicationRecord
  self.table_name = "marketplace_listing_events"

  belongs_to :listing, class_name: "Marketplace::Listing", inverse_of: :events
  belongs_to :user, optional: true

  serialize :metadata, coder: JSON

  EVENT_TYPES = %w[click cart purchase return review shipped delivered cancelled].freeze

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true

  scope :recent, ->(days = 7) { where("occurred_at >= ?", days.days.ago) }
  scope :of_type, ->(type) { where(event_type: type) }
end
