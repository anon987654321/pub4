# frozen_string_literal: true

class WardrobeMediaJob < ApplicationJob
  queue_as :bulk

  VARIANTS = {
    thumb: { resize_to_limit: [ 240, 240 ] },
    card: { resize_to_limit: [ 720, 960 ] }
  }.freeze

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
      # Inline variants — avoids doubling bulk-queue depth per upload on a 1-CPU host.
      Shared::MediaProcessingJob.perform_now("Item", item.id, "photos", variants: VARIANTS)
    end
    Shared::EventEmitter.call("amber.photo.queued", item_id: item.id) if defined?(Shared::EventEmitter)
    item.extract_dominant_color! if item.photos.attached?
    enqueue_once(SegmentGarmentImageJob, item.id) if item.photos.attached?
    enqueue_once(RemoveBackgroundJob, item.id) if item.photos.attached?
    enqueue_once(EmbedGarmentJob, item.id) if item.photos.attached?
    enqueue_once(CalculateSustainabilityJob, item.id)

    if item.photos.attached?
      if Shared::PostproProcessor.apply_to_record!(item, :photos, preset: "portrait", replace: true)
        Rails.logger.info("postpro portrait grade applied to item #{item.id}")
      end
    end
  end

  private

  def enqueue_once(job_class, item_id)
    return if job_pending?(job_class, item_id)

    job_class.perform_later(item_id)
  end

  def job_pending?(job_class, item_id)
    needle = "Item/#{item_id}"
    SolidQueue::Job.where(finished_at: nil, class_name: job_class.name)
      .where("arguments LIKE ?", "%#{needle}%").exists?
  rescue StandardError => e
    Rails.logger.warn("job_pending? check failed for #{job_class.name}/#{item_id}: #{e.message}")
    false
  end
end
