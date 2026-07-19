# frozen_string_literal: true

# Deprecated name kept for in-flight queues. Does not remove backgrounds.
# Real matting is planned; status is honest.
class RemoveBackgroundJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    if item.analysis_status.to_s.start_with?("photo_polish")
      Rails.logger.info("RemoveBackgroundJob item=#{item.id} skipped (already polished)")
      return
    end

    item.update!(analysis_status: "photo_polish_skipped") if item.respond_to?(:analysis_status=)
    Rails.logger.info("RemoveBackgroundJob item=#{item.id}: no ML matting; use WardrobeMediaJob portrait polish")
  end
end
