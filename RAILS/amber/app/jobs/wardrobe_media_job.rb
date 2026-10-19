# frozen_string_literal: true

# Upload pipeline: variants, dominant colour, single portrait polish, local fingerprint, sustainability.
# Does NOT claim ML garment segmentation or background removal — one postpro portrait pass only.
class WardrobeMediaJob < ApplicationJob
  queue_as :bulk

  # One job per item holds the semaphore from enqueue until it finishes, so an
  # edit that enqueues again while the first still waits is discarded instead
  # of polishing the same photos twice. The duration outlasts amber's hourly
  # drain window, or the semaphore would expire before the job ran.
  limits_concurrency to: 1, key: ->(item_id) { item_id }, duration: 2.hours, on_conflict: :discard

  # Keep in lockstep with Item::PHOTO_VARIANTS (named ActiveStorage variants).
  VARIANTS = Item::PHOTO_VARIANTS

  def perform(item_id)
    item = Item.find(item_id)
    if defined?(Shared::MediaProcessingJob)
      Shared::MediaProcessingJob.perform_now("Item", item.id, "photos", variants: VARIANTS)
    end
    Shared::EventEmitter.call("amber.photo.queued", item_id: item.id) if defined?(Shared::EventEmitter)

    if item.photos.attached?
      item.extract_dominant_color!
      polish_ok = if defined?(Shared::PostproProcessor)
        Shared::PostproProcessor.apply_to_record!(item, :photos, preset: "portrait", replace: true)
      else
        false
      end
      status = polish_ok ? "photo_polish_done" : "photo_polish_skipped"
      item.update!(analysis_status: status) if item.respond_to?(:analysis_status=)
      Rails.logger.info("WardrobeMediaJob item=#{item.id} photo_polish=#{status}")
    else
      item.update!(analysis_status: "no_photos") if item.respond_to?(:analysis_status=)
    end

    FingerprintGarmentJob.perform_later(item.id)
    CalculateSustainabilityJob.perform_later(item.id)
  end
end
