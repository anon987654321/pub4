# frozen_string_literal: true

class Marketplace::Order < ApplicationRecord
  include Shared::Notifiable
  include Shared::ActivityTrackable

  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"

  STATUSES = %w[pending accepted declined completed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true
  before_validation { self.status ||= "pending"; self.quantity ||= 1 }

  def seller = listing.user

  # Cart-like helpers (pending orders act as the buyer's cart)
  def total_cents = (listing.price_cents || 0) * (quantity || 1)
  def total_display = "#{total_cents / 100.0} #{listing.currency || 'NOK'}"

  def accept!
    update!(status: "accepted")
    deliver_notification(buyer, title: "Offer accepted", body: "Your offer for #{listing.title} was accepted.", source: self)
  end

  def decline!
    update!(status: "declined")
    deliver_notification(buyer, title: "Offer declined", body: "Your offer for #{listing.title} was declined.", source: self)
  end
end
