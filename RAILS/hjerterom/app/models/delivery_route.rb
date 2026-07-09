# frozen_string_literal: true

class DeliveryRoute < ApplicationRecord
  enum :status, { planned: 0, active: 1, completed: 2, cancelled: 3 }, default: :planned

  belongs_to :volunteer, optional: true
  has_many :delivery_stops, -> { order(:sequence) }, dependent: :destroy

  validates :route_date, presence: true
end