# frozen_string_literal: true

module Marketplace
  class RecalculateRankingJob < ApplicationJob
    queue_as :default

    def perform(listing_id = nil)
      if listing_id
        listing = Marketplace::Listing.find_by(id: listing_id)
        Marketplace::RankingService.new(listing).recalculate! if listing
        return
      end

      Marketplace::Listing.live.find_each do |listing|
        Marketplace::RankingService.new(listing).recalculate!
      end
    end
  end
end
