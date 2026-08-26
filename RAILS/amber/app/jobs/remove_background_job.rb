# frozen_string_literal: true

# Nothing in this tree enqueues this class any more. It stays because deleting
# a job class is only safe once the queue holding its rows has drained, and
# amber's has not: rc.d/<app>_jobs records 103 jobs enqueued and 0 finished on
# vm23 (2026-08-12), because no Solid Queue supervisor has ever run there. A
# queued row naming a deleted class raises NameError the first time a worker
# finally picks it up.
#
# Removal precondition, on the box, after the worker has run:
#
#   sqlite3 -readonly /home/amber/app/storage/production_queue.sqlite3 \
#     "select count(*) from solid_queue_jobs where class_name = 'RemoveBackgroundJob';"
#
# Zero, and this file goes.
#
# Deprecated name kept for in-flight queues. Does not remove backgrounds.
# Real matting is planned; status is honest.
class RemoveBackgroundJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    if item.analysis_status.to_s.start_with?("photo_polish")
      Rails.logger.info("RemoveBackgroundJob item=#{item.id} skipped (already polished)")
      return
    end

    item.update!(analysis_status: "photo_polish_skipped") if item.respond_to?(:analysis_status=)
    Rails.logger.info("RemoveBackgroundJob item=#{item.id}: no ML matting; use WardrobeMediaJob portrait polish")
  end
end
