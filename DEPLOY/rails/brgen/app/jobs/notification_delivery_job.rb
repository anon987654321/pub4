# frozen_string_literal: true

class NotificationDeliveryJob < ApplicationJob
  queue_as :critical

  def perform(notification_id)
    notification = Notification.find(notification_id)
    notification.broadcast_prepend_to("brgen:notifications:#{notification.user_id}") if notification.respond_to?(:broadcast_prepend_to)
    Shared::EventEmitter.call("brgen.notification.delivered", notification_id: notification.id, user_id: notification.user_id) if defined?(Shared::EventEmitter)
  end
end
