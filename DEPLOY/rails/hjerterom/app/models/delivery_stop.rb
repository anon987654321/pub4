# frozen_string_literal: true

class DeliveryStop < ApplicationRecord
  enum :stop_kind, { pickup: 0, dropoff: 1 }, default: :pickup

  belongs_to :delivery_route
  belongs_to :reference, polymorphic: true, optional: true

  validates :label, presence: true
  validates :sequence, numericality: { greater_than_or_equal_to: 0 }
end