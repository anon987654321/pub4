# frozen_string_literal: true

class Dating::ProfileMediaJob < ApplicationJob
  queue_as :bulk

  VARIANTS = {
    thumb: { resize_to_limit: [ 400, 600 ], format: :webp },
    card: { resize_to_limit: [ 800, 1_200 ], format: :webp }
  }.freeze

  def perform(profile_id)
    profile = Dating::Profile.find_by(id: profile_id)
    return unless profile&.photos&.attached?

    Shared::MediaProcessingJob.perform_now("Dating::Profile", profile.id, "photos", variants: VARIANTS)
  end
end
