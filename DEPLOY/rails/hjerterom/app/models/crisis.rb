# frozen_string_literal: true

class Crisis < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  validates :title, :phone, presence: true

  scope :around_clock, -> { where(available_24h: true) }
  scope :for_country,  ->(c) { where(country: c) }
end
