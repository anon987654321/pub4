# frozen_string_literal: true
# AN613: Saved search alerts

module Marketplace
  class SavedSearchAlertJob < ApplicationJob
    queue_as :bulk

    def perform
      SavedSearch.find_each do |search|
        results = Listing.search(search.query, city: search.city).where("created_at > ?", 24.hours.ago)
        next if results.empty?

        search.user.notifications.create!(body: "#{results.count} new listings for #{search.query}")
        Turbo::StreamsChannel.broadcast_append_to(search.user, target: "notifications", partial: "notifications/notification", locals: { body: "#{results.count} new matches" })
      end
    end
  end
end