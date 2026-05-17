class Marketplace::Order < ApplicationRecord
  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"

  STATUSES = %w[pending accepted declined completed].freeze

  validates :status, inclusion: { in: STATUSES }
  before_validation { self.status ||= "pending" }

  def seller = listing.user
  def accept! = update!(status: "accepted")
  def decline! = update!(status: "declined")
end
