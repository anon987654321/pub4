# frozen_string_literal: true

module Marketplace
  class UpdateSellerScoresJob < ApplicationJob
    queue_as :default

    def perform
      Marketplace::Store.find_each do |store|
        Marketplace::SellerScoreCalculator.new(store).apply!
      end

      User.joins(:marketplace_listings)
        .where(marketplace_listings: { store_id: nil })
        .distinct.find_each do |user|
          Marketplace::SellerScoreCalculator.new(user).apply!
        end
    end
  end
end
