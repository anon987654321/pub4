# frozen_string_literal: true

class Domain < ApplicationRecord
  enum :state, {
    pending: "pending",
    active: "active",
    warning: "warning",
    hold: "hold",
    parked: "parked",
    deleted: "deleted"
  }

  has_many :orders, dependent: :restrict_with_exception
  has_many :audit_events, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: true
  validates :state, presence: true
end
