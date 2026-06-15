# frozen_string_literal: true

class Transfer < ApplicationRecord
  belongs_to :partner
  belongs_to :beneficiary, optional: true
  belongs_to :box, optional: true

  enum :status, { pending: 0, in_transit: 1, delivered: 2, canceled: 3 }

  validates :scheduled_at, presence: true, on: :create

  scope :recent, -> { order(scheduled_at: :desc) }
end