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

  validates :name, presence: true, uniqueness: true
  validates :state, presence: true
end
