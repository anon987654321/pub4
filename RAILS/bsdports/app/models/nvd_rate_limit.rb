# frozen_string_literal: true

class NvdRateLimit < ApplicationRecord
  NAME = "nvd"

  def self.interval
    ENV["NVD_API_KEY"].present? ? 0.6.seconds : 6.seconds
  end

  # Reserve a distinct delayed-job slot with compare-and-swap. This avoids
  # relying on row locks that SQLite does not implement as row-level locks.
  def self.reserve_slot
    row = create_or_find_by!(name: NAME)

    loop do
      now = Time.current
      previous = row.reload.next_allowed_at
      slot = [ previous || now, now ].max
      relation = where(id: row.id)
      relation = previous ? relation.where(next_allowed_at: previous) : relation.where(next_allowed_at: nil)
      changed = relation.update_all(next_allowed_at: slot + interval, updated_at: now)
      return slot if changed == 1
    end
  end

  # Atomically reserve the actual request start too. Scheduled jobs can become
  # overdue while a queue is drained; this check prevents overdue work bursting
  # against NVD even when its original reserved time has passed.
  def self.claim_or_defer
    row = create_or_find_by!(name: NAME)

    loop do
      now = Time.current
      previous = row.reload.last_request_at
      allowed_at = [ previous ? previous + interval : now, now ].max
      return allowed_at if allowed_at > now

      relation = where(id: row.id)
      relation = previous ? relation.where(last_request_at: previous) : relation.where(last_request_at: nil)
      changed = relation.update_all(last_request_at: now, updated_at: now)
      return nil if changed == 1
    end
  end
end
