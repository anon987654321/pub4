# frozen_string_literal: true

# Expired location pings and fortnight-old crossings, swept on a schedule.
#
# Both deletes used to run inside PathCrossingsController#index and every
# PathCrossingRecorder#call, so a page read and each location ping was a
# table-wide write. Readers already ignore expired pings (LocationPing.active),
# so deleting them is housekeeping, not correctness, and can wait for this.
class Dating::PathCrossingSweepJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: "dating-path-crossing-sweep", duration: 15.minutes, on_conflict: :discard

  CROSSINGS_KEPT_FOR = 14.days

  def perform(now: Time.current)
    Dating::LocationPing.where(expires_at: ..now).delete_all
    Dating::PathCrossing.where(crossed_at: ...(now - CROSSINGS_KEPT_FOR)).delete_all
  end
end
