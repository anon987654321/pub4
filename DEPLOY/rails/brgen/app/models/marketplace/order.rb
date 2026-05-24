# frozen_string_literal: true

class Marketplace::Order < ApplicationRecord
  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"

  STATUSES = %w[pending accepted declined completed].freeze

  validates :status, inclusion: { in: STATUSES }
  before_validation { self.status ||= "pending" }

  def seller = listing.user

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
