# frozen_string_literal: true

module Shared
  class NotificationReadReflex < Shared::ApplicationReflex
    # The inbox's own card. A separate notification_row partial, with its own
    # "notification-<id>" id, matched nothing the inbox draws.
    PARTIAL = "notifications/notification"

    def mark_read
      notification = current_user.notifications.find(element.dataset["notification-id"])
      notification.mark_as_read!
      morph "##{ActionView::RecordIdentifier.dom_id(notification)}", render(partial: PARTIAL, locals: { notification: })
    end

    private

    def current_user
      Current.user
    end
  end
end
