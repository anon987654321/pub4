# frozen_string_literal: true

class Participant < ApplicationRecord
  enum :kind, {
    registrar: "registrar",
    reseller: "reseller",
    dns_provider: "dns_provider",
    technical_partner: "technical_partner"
  }

  enum :status, {
    pending: "pending",
    sandbox: "sandbox",
    active: "active",
    suspended: "suspended",
    terminated: "terminated"
  }

  serialize :metadata, coder: JSON

  has_many :orders, dependent: :restrict_with_exception

  validates :name, :kind, :status, presence: true
  validates :external_id, uniqueness: true, allow_nil: true
end
