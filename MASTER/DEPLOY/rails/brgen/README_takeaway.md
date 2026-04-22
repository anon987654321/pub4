# frozen_string_literal: true

# == Restaurant
# Represents a dining location.
class Restaurant < ApplicationRecord
  has_many :menu_items, dependent: :destroy
  has_many :orders, dependent: :nullify

  validates :name, :address, presence: true

  # Geocoder integration – update coordinates only when the address changes.
  geocoded_by :address
  after_validation :geocode, if: :will_save_change_to_address?
end

# == MenuItem
# An item on a restaurant's menu.
class MenuItem < ApplicationRecord
  belongs_to :restaurant

  # Availability states.
  enum availability: { available: 0, sold_out: 1 }

  # Store monetary value as integer cents, expose as a Money object.
  monetize :price_cents

  validates :name, :price_cents, presence: true

  # Scope for currently available items.
  scope :available, -> { where(availability: :available) }
end

# == Order
# A food order placed by a user.
class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user

  # Order lifecycle states.
  enum status: {
    placed:    0,
    accepted:  1,
    preparing: 2,
    dispatched: 3,
    delivered: 4,
    canceled:  5
  }

  validates :status, presence: true

  # Scope for orders that are still in progress.
  scope :in_progress, -> { where.not(status: %i[delivered canceled]) }
end