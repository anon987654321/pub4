# frozen_string_literal: true

class Box < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  include Shared::GeoLocatable
  enum :status, { planning: 0, packing: 1, ready: 2, delivered: 3, cancelled: 4 }, default: :planning

  belongs_to :beneficiary, optional: true
  has_many :food_items, dependent: :nullify

  validates :week_start, presence: true

  scope :current, -> { where(week_start: Date.current.beginning_of_week) }
  scope :open, -> { where(status: %i[planning packing ready]) }

  after_create_commit { broadcast_append_later_to "hjerterom:boxes" }
  after_update_commit { broadcast_replace_later_to "hjerterom:boxes" }
end
