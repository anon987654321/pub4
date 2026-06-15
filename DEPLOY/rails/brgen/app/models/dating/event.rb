# frozen_string_literal: true

class Dating::Event < ApplicationRecord
  self.table_name = "dating_events"

  belongs_to :user
  has_many :rsvps, class_name: "Dating::EventRsvp", foreign_key: :dating_event_id, dependent: :destroy
  has_many :attendees, through: :rsvps, source: :user

  validates :title, :starts_at, presence: true

  scope :upcoming, -> { where("starts_at >= ?", Time.current).order(:starts_at) }
  scope :in_city, ->(city) { city.present? ? where(city:) : all }
  scope :nearby, ->(lat, lng, km = 25) {
    return all if lat.blank? || lng.blank?

    where("ABS(latitude - ?) < ? AND ABS(longitude - ?) < ?", lat.to_f, km / 111.0, lng.to_f, km / 111.0)
  }
end