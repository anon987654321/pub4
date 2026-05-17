class Crisis < ApplicationRecord
  validates :title, :phone, presence: true

  scope :around_clock, -> { where(available_24h: true) }
  scope :for_country,  ->(c) { where(country: c) }
end
