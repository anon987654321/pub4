# frozen_string_literal: true

class ActivityEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  validates :source_vertical, :event_name, :object_type, :object_id, presence: true

  scope :visible, -> { where(moderation_state: "clean") }
  scope :recent, -> { order(created_at: :desc) }
  # Never surface private activity on a public profile (dating likes are private).
  scope :public_only, -> { where(visibility: "public") }

  # Public vertical births for the city-home strip. Posts stay on the feed;
  # this is interconnection, not a second timeline.
  HOME_STRIP_EVENTS = %w[
    ListingCreated
    TakeawayRestaurantCreated
    MarketplaceStoreCreated
    MarketplaceDealCreated
    VideoPublished
  ].freeze

  def self.for_city_home(city, limit: 8)
    return none unless city

    visible.public_only.where(event_name: HOME_STRIP_EVENTS).recent.limit(limit * 4).select { |event|
      in_city?(event, city)
    }.first(limit)
  end

  def self.in_city?(event, city)
    labels = [city.try(:name), city.try(:domain)].compact
    if event.locality.present? && labels.any? { |label| event.locality.to_s.casecmp?(label.to_s) }
      return true
    end

    record = event.object_type.to_s.safe_constantize&.find_by(id: event.object_id)
    return false unless record

    city_id = record.try(:city_id)
    city_id = record.try(:channel).try(:city_id) if city_id.blank?
    city_id = record.try(:listing).try(:city_id) if city_id.blank?
    return city_id == city.id if city_id.present?

    event.locality.blank?
  end
end
