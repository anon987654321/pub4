# frozen_string_literal: true

class IdentityVerification < ApplicationRecord
  belongs_to :user

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }, default: :pending
  enum :kind, { creator: "creator", merchant: "merchant", stylist: "stylist", human: "human" }, default: :human

  validates :kind, :status, presence: true
end
