# frozen_string_literal: true

# What a room or a flat carries: rent, size, and the date it is free.
class Marketplace::HousingDetail < ApplicationRecord
  HOUSING_TYPES = %w[room flat house sublet].freeze

  belongs_to :listing, class_name: "Marketplace::Listing"

  validates :housing_type, inclusion: { in: HOUSING_TYPES }, allow_blank: true
  # Rent is the number people search on, so it is the one that has to be there:
  # a housing advert without it is a phone call, which is what a listing exists
  # to replace.
  validates :rent_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :deposit_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :rooms, numericality: { greater_than: 0 }, allow_nil: true
  validates :size_sqm, numericality: { greater_than: 0 }, allow_nil: true

  def rent_display = Shared::MoneyDisplay.format(rent_cents)
  def deposit_display = deposit_cents.present? ? Shared::MoneyDisplay.format(deposit_cents) : nil
end
