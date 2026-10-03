# frozen_string_literal: true

module Shared
  class OnboardingArtworkJob < ApplicationJob
    queue_as :bulk

    limits_concurrency to: 1,
      key: ->(surface:, city_name:) { "onboarding-artwork-#{surface}-#{city_name.to_s.downcase}" },
      duration: 15.minutes,
      on_conflict: :discard

    def perform(surface:, city_name:)
      Shared::OnboardingArtwork.generate(surface:, city: city_name)
    ensure
      Rails.cache.delete(Shared::OnboardingArtwork.cache_key(surface:, city: city_name))
    end
  end
end