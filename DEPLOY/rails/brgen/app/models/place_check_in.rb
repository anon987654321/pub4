# frozen_string_literal: true

class PlaceCheckIn < ApplicationRecord
  belongs_to :place
  belongs_to :user

  validates :checked_in_at, presence: true
  validates :note, length: { maximum: 280 }, allow_blank: true

  scope :recent, -> { order(checked_in_at: :desc) }

  after_create_commit do
    record_activity!("PlaceCheckedIn", source_vertical: "maps", actor: user) rescue nil
  end

  private

  def record_activity!(event_type, **payload)
    return unless defined?(Shared::ActivityTrackable)

    ActivityEvent.create!(
      event_type: event_type,
      actor: user,
      subject: place,
      source_vertical: payload[:source_vertical],
      visibility: payload.fetch(:visibility, "public"),
      metadata: { place_id: place_id, place_name: place.name }
    )
  end
end