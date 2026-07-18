# frozen_string_literal: true

# Garment "segmentation" pass: grade primary photo through shared postpro
# (portrait crop/polish). Full ML segmentation can replace this later without
# changing the job contract or analysis_status terminals.
class SegmentGarmentImageJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    unless item.photos.attached?
      item.update!(analysis_status: "segmentation_skipped") if item.respond_to?(:analysis_status=)
      return
    end

    ok = Shared::PostproProcessor.apply_to_record!(item, :photos, preset: "portrait", replace: false)
    status = ok ? "segmentation_done" : "segmentation_failed"
    item.update!(analysis_status: status) if item.respond_to?(:analysis_status=)
    Rails.logger.info("SegmentGarmentImageJob item=#{item.id} status=#{status}")
  rescue StandardError => e
    Rails.logger.error("SegmentGarmentImageJob item=#{item_id}: #{e.class}: #{e.message}")
    item = Item.find_by(id: item_id)
    item&.update(analysis_status: "segmentation_failed") if item.respond_to?(:analysis_status=)
    raise
  end
end
