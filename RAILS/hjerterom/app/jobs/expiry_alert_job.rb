# frozen_string_literal: true

class ExpiryAlertJob < ApplicationJob
  queue_as :critical

  WINDOW = 48.hours

  def perform
    FoodListing.where(status: "available", available_until: Time.current..WINDOW.from_now).find_each do |listing|
      Rails.logger.info("hjerterom: expiry alert listing=#{listing.id} available_until=#{listing.available_until}")
    end
  end
end
