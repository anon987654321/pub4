# frozen_string_literal: true

class SegmentGarmentImageJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    GarmentSegmentationService.call(item)
    RemoveBackgroundJob.perform_later(item_id)
  end
end
