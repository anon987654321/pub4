# frozen_string_literal: true

# Deprecated name kept for in-flight queues. Portrait polish lives in WardrobeMediaJob.
# Not ML segmentation — marks honest status and no-ops if polish already done.
class SegmentGarmentImageJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    status = item.analysis_status.to_s
    return if status.start_with?("photo_polish")

    unless item.photos.attached?
      item.update!(analysis_status: "photo_polish_skipped") if item.respond_to?(:analysis_status=)
      return
    end

    ok = defined?(Shared::PostproProcessor) &&
      Shared::PostproProcessor.apply_to_record!(item, :photos, preset: "portrait", replace: false)
    item.update!(analysis_status: ok ? "photo_polish_done" : "photo_polish_failed") if item.respond_to?(:analysis_status=)
  rescue StandardError => e
    Rails.logger.error("SegmentGarmentImageJob item=#{item_id}: #{e.class}: #{e.message}")
    Item.find_by(id: item_id)&.update(analysis_status: "photo_polish_failed")
    raise
  end
end
