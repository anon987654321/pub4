# frozen_string_literal: true

class RemoveBackgroundJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    Rails.logger.info("Amber background-removal placeholder for item=#{item.id}")
    item.update!(analysis_status: "background_removal_pending") if item.respond_to?(:analysis_status)
  end
end
