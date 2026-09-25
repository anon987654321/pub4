# frozen_string_literal: true

class Order < ApplicationRecord
  enum :operation, {
    create: "create",
    renew: "renew",
    delete: "delete",
    restore: "restore"
  }

  enum :state, {
    pending: "pending",
    payment_pending: "payment_pending",
    registry_pending: "registry_pending",
    active: "active",
    reconciliation: "reconciliation",
    failed: "failed",
    refunded: "refunded"
  }

  belongs_to :domain
  belongs_to :registrant
  belongs_to :participant, optional: true
  has_many :registry_operations, dependent: :restrict_with_exception

  validates :operation, :state, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: true
  validates :currency, length: { is: 3 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
