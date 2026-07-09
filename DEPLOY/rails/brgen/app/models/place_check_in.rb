# frozen_string_literal: true

class PlaceCheckIn < ApplicationRecord
  include Shared::ActivityTrackable

  belongs_to :place
  belongs_to :user

  validates :checked_in_at, presence: true
  validates :note, length: { maximum: 280 }, allow_blank: true

  scope :recent, -> { order(checked_in_at: :desc) }

  after_create_commit do
    record_activity!("PlaceCheckedIn", source_vertical: "maps", actor: user)
  end
end