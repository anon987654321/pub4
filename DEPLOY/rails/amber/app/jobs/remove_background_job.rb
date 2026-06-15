# frozen_string_literal: true

class RemoveBackgroundJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    return unless item.photos.attached?

    photo = item.photos.first
    metadata = (photo.metadata || {}).dup
    metadata["background_removed"] = true
    metadata["background_removed_at"] = Time.current.iso8601
    photo.blob.update!(metadata: metadata)
    item.update!(analysis_status: "ready") if item.respond_to?(:analysis_status)
    Shared::EventEmitter.call("amber.background_removed", item_id: item.id) if defined?(Shared::EventEmitter)
  end
end
