# frozen_string_literal: true

class FoodExpiryAlertJob < ApplicationJob
  queue_as :default

  ALERT_WINDOW = 48.hours

  def perform
    FoodListing.where(status: "available")
               .where(available_until: Time.current..ALERT_WINDOW.from_now)
               .find_each do |listing|
      Shared::EventEmitter.call(
        "hjerterom.food.expiring",
        listing_id: listing.id,
        title: listing.title,
        available_until: listing.available_until.iso8601
      ) if defined?(Shared::EventEmitter)
    end
  end
end