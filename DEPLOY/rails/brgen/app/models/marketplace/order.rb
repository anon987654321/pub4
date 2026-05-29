# frozen_string_literal: true

class Marketplace::Order < ApplicationRecord
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
    notify_buyer!("Offer accepted", "Your offer for #{listing.title} was accepted.")
  end

  def decline!
    update!(status: "declined")
    notify_buyer!("Offer declined", "Your offer for #{listing.title} was declined.")
  end

  private

  def notify_buyer!(title, body)
    return unless defined?(Notification)

    buyer.notifications.create!(title: title, body: body, source_type: self.class.name, source_id: id)
  end
end
