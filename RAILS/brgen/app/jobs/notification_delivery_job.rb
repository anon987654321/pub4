# frozen_string_literal: true

# Enqueued by nothing in this tree. Kept, not deleted, for the reason the amber
# job shims are: brgen's Solid Queue has 1670 jobs enqueued and 0 finished on
# vm23 (rc.d/brgen_jobs, 2026-08-12), so a row naming this class may still be
# sitting in it. Deleting the class turns that row into a NameError the first
# time the supervisor runs.
#
# Removal precondition, on the box, after the worker has run:
#
#   sqlite3 -readonly /home/brgen/app/storage/production_queue.sqlite3 \
#     "select count(*) from solid_queue_jobs where class_name = 'NotificationDeliveryJob';"
#
# Zero, and this file goes.
#
class NotificationDeliveryJob < ApplicationJob
  queue_as :critical

  def perform(notification_id)
    notification = Notification.find(notification_id)
    notification.broadcast_prepend_to("brgen:notifications:#{notification.user_id}") if notification.respond_to?(:broadcast_prepend_to)
    Shared::EventEmitter.call("brgen.notification.delivered", notification_id: notification.id, user_id: notification.user_id) if defined?(Shared::EventEmitter)
  end
end
