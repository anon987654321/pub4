# frozen_string_literal: true

class UnderusedItemNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    scope = user_id ? User.where(id: user_id) : User.all
    scope.find_each do |user|
      items = user.items.active_wardrobe.never_worn.where("created_at < ?", 30.days.ago).limit(5)
      next if items.empty?

      Shared::EventEmitter.call(
        "amber.underused_items",
        user_id: user.id,
        item_ids: items.pluck(:id),
        count: items.size
      ) if defined?(Shared::EventEmitter)
    end
  end
end