# frozen_string_literal: true

class Registrant < ApplicationRecord
  enum :verification_status, {
    pending: "pending",
    verified: "verified",
    rejected: "rejected"
  }

  has_many :orders, dependent: :restrict_with_exception

  validates :email, :country_code, presence: true
  validates :email, uniqueness: true
  validates :country_code, length: { is: 2 }
end
