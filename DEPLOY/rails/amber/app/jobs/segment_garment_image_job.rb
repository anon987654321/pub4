# frozen_string_literal: true

class SegmentGarmentImageJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    Rails.logger.info("Amber segmentation placeholder for item=#{item.id}")
    item.update!(analysis_status: "segmentation_pending") if item.respond_to?(:analysis_status)
  end
end
