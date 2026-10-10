# frozen_string_literal: true

class Dating::LocationPing < ApplicationRecord
  self.table_name = "dating_location_pings"

  belongs_to :city
  belongs_to :user
  belongs_to :neighborhood, optional: true

  validates :latitude, numericality: { in: -90..90 }
  validates :longitude, numericality: { in: -180..180 }
  validates :expires_at, presence: true

  scope :active, ->(now = Time.current) { where("expires_at > ?", now) }
end
