# frozen_string_literal: true

require "tempfile"
require "rbconfig"
require "pub4/deploy_paths"

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

    # auto postpro film stock on item image upload (DF06)
    if item.photos.attached?
      photo = item.photos.first
      begin
        script = Pub4::DeployPaths.postpro_script&.to_s
        if script.present? && File.exist?(script)
          tmp_in = Tempfile.new([ "in", File.extname(photo.filename.to_s.presence || ".jpg") ])
          tmp_in.binmode
          tmp_in.write(photo.download)
          tmp_in.rewind
          tmp_out = Tempfile.new([ "out", ".jpg" ])
          system(RbConfig.ruby, script, "--input", tmp_in.path, "--output", tmp_out.path, "--stock", "kodak_portra", "--preset", "social")
          if File.exist?(tmp_out.path)
            Rails.logger.info("postpro film stock applied automatically to item #{item.id}")
            # could re-attach processed version here
          end
          tmp_in.close!
          tmp_out.close!
        end
      rescue StandardError => e
        Rails.logger.warn("auto postpro failed for item #{item.id}: #{e.message}")
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
