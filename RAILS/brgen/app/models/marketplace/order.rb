# frozen_string_literal: true

class Marketplace::Order < ApplicationRecord
  include Shared::Notifiable
  tracks_activity created: "MarketplaceOrder", source_vertical: "marketplace", actor: :buyer

  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"

  STATUSES = %w[pending accepted declined completed].freeze

  validates :status, inclusion: { in: STATUSES }
  before_validation { self.status ||= "pending" }

  def seller = listing.user

  # Cart-like helpers (pending orders act as the buyer's cart)
  def total_cents = (listing.price_cents || 0) * (quantity.presence || 1).to_i
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
