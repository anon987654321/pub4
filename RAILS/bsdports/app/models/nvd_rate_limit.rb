# frozen_string_literal: true

class NvdRateLimit < ApplicationRecord
  NAME = "nvd"

  # Claim the next request without sleeping in any request or worker thread.
  # A conditional UPDATE is the serialized reservation: only one process can
  # move a row whose slot has expired. Other processes receive its next time.
  def self.claim_or_defer
    now = Time.current
    interval = ENV["NVD_API_KEY"].present? ? 0.6.seconds : 6.seconds
    row = create_or_find_by!(name: NAME)
    claimed = where(id: row.id)
      .where("next_allowed_at IS NULL OR next_allowed_at <= ?", now)
      .update_all(next_allowed_at: now + interval, updated_at: now)

    return nil if claimed == 1

    row.reload.next_allowed_at || now + interval
  end
end
