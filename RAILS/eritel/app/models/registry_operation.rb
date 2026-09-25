# frozen_string_literal: true

class RegistryOperation < ApplicationRecord
  enum :state, {
    pending: "pending",
    succeeded: "succeeded",
    failed: "failed",
    reconciliation: "reconciliation"
  }

  belongs_to :order

  validates :operation, :state, :request_id, presence: true
  validates :request_id, uniqueness: true
end
