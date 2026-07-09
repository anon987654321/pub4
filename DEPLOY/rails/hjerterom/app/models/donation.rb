# frozen_string_literal: true

class Donation < ApplicationRecord
  # Engine-ize Shared
  include Shared::Reactable
  include Shared::Notifiable
  include Shared::GeoLocatable
  enum :status, { pending: 0, accepted: 1, packed: 2, distributed: 3, cancelled: 4 }, default: :pending

  belongs_to :donor, optional: true
  has_many :food_items, dependent: :destroy

  validates :source_name, presence: true
  validates :pickup_window, presence: true, allow_blank: true

  scope :active, -> { where.not(status: :cancelled) }
  scope :needs_action, -> { where(status: %i[pending accepted]) }

  after_create_commit { broadcast_prepend_later_to "hjerterom:donations" }
  after_update_commit { broadcast_replace_later_to "hjerterom:donations" }
end
