# frozen_string_literal: true

class WardrobeMediaJob < ApplicationJob
  queue_as :media

  VARIANTS = {
    thumb: { resize_to_limit: [240, 240] },
    card: { resize_to_limit: [720, 960] }
  }.freeze

  def perform(item_id)
    item = Item.find(item_id)
    if defined?(Shared::MediaProcessingJob)
      Shared::MediaProcessingJob.perform_later("Item", item.id, "photos", variants: VARIANTS)
    end
    Shared::EventEmitter.call("amber.photo.queued", item_id: item.id) if defined?(Shared::EventEmitter)
    item.extract_dominant_color! if item.photos.attached?
  end
end
