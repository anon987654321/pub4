# frozen_string_literal: true

# Upload pipeline: variants, dominant colour, single portrait polish, local fingerprint, sustainability.
# Does NOT claim ML garment segmentation or background removal — one postpro portrait pass only.
class WardrobeMediaJob < ApplicationJob
  queue_as :bulk

  # Keep in lockstep with Item::PHOTO_VARIANTS (named ActiveStorage variants).
  VARIANTS = Item::PHOTO_VARIANTS

  def self.pending_for?(item_id)
    needle = "Item/#{item_id}"
    SolidQueue::Job.where(finished_at: nil, class_name: name)
      .where("arguments LIKE ?", "%#{needle}%").exists?
  rescue StandardError => e
    Rails.logger.warn("pending_for? check failed for item #{item_id}: #{e.message}")
    false
  end

  def self.enqueue_for(item_id)
    return if pending_for?(item_id)

    perform_later(item_id)
  end

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

    enqueue_once(FingerprintGarmentJob, item.id)
    enqueue_once(CalculateSustainabilityJob, item.id)
  end

  private

  def enqueue_once(job_class, item_id)
    return if job_pending?(job_class, item_id)

    job_class.perform_later(item_id)
  end

  def job_pending?(job_class, item_id)
    needle = item_id.to_s
    SolidQueue::Job.where(finished_at: nil, class_name: job_class.name)
      .where("arguments LIKE ?", "%#{needle}%").exists?
  rescue StandardError => e
    Rails.logger.warn("job_pending? check failed for #{job_class.name}/#{item_id}: #{e.message}")
    false
  end
end
