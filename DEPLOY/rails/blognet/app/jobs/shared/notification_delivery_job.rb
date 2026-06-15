# frozen_string_literal: true
# AN301: Named job class for notification delivery

module Shared
  class NotificationDeliveryJob < ApplicationJob
    include Shared::ExternalApiRetry

    queue_as :critical
    limits_concurrency to: 5, key: ->(*_) { "notifications" }

    def perform(notification_id)
      notification = Notification.find(notification_id)
      notification.deliver!
    end
  end
end