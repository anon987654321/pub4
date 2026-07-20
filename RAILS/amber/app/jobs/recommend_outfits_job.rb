# frozen_string_literal: true

class RecommendOutfitsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 2, key: ->(user_id) { "llm-recommend-outfits-#{user_id}" }, duration: 5.minutes

  def perform(user_id, occasion: nil, season: nil)
    user = User.find(user_id)
    suggestions = WardrobeAi.new(user).suggest_outfits(occasion:, season:)

    Array(suggestions).each do |suggestion|
      user.recommendations.create!(
        kind: "outfit",
        reason: suggestion["description"].presence || suggestion["reason"].presence || "AI outfit suggestion",
        metadata: suggestion
      )
    end
  end
end
