# frozen_string_literal: true

module Shared
  class NotificationReadReflex < Shared::ApplicationReflex
    def mark_read
      notification = current_user.notifications.find(element.dataset["notification-id"])
      notification.mark_as_read!
      morph "##{dom_id(notification)}",
            render(partial: "notifications/notification_row", locals: { notification: notification })
    end

    private

    def current_user
      Current.user
    end

    def dom_id(record)
      ActionView::RecordIdentifier.dom_id(record)
    end
  end
end