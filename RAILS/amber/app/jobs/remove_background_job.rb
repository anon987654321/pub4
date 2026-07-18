# frozen_string_literal: true

# Wardrobe background treatment via shared postpro boundary (MASTER tools/postpro).
# Sets a terminal analysis_status so the UI does not stall on "pending".
class RemoveBackgroundJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    unless item.photos.attached?
      item.update!(analysis_status: "background_removal_skipped") if item.respond_to?(:analysis_status=)
      return
    end

    ok = Shared::PostproProcessor.apply_to_record!(item, :photos, preset: "portrait", replace: false)
    status = ok ? "background_removal_done" : "background_removal_failed"
    item.update!(analysis_status: status) if item.respond_to?(:analysis_status=)
    Rails.logger.info("RemoveBackgroundJob item=#{item.id} status=#{status}")
  rescue StandardError => e
    Rails.logger.error("RemoveBackgroundJob item=#{item_id}: #{e.class}: #{e.message}")
    item = Item.find_by(id: item_id)
    item&.update(analysis_status: "background_removal_failed") if item.respond_to?(:analysis_status=)
    raise
  end
end
