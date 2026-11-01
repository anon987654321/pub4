# frozen_string_literal: true

module Shared
  class NotificationReadReflex < Shared::ApplicationReflex
    def mark_read
      notification = current_user.notifications.find(element.dataset["notification-id"])
      notification.mark_as_read!
      morph "#notification-#{notification.id}",
            render(partial: "notifications/notification_row", locals: { notification: })
    end

    private

    def current_user
      Current.user
    end
  end
end
