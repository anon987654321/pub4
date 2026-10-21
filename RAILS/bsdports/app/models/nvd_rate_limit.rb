# frozen_string_literal: true

class NvdRateLimit < ApplicationRecord
  NAME = "nvd"

  # Claim a shared request slot without sleeping in a web or job thread.
  # The table is the cross-process source of truth; with_lock serializes
  # reservations and the returned time is a scheduling hint, not a delay.
  def self.claim_or_defer
    interval = ENV["NVD_API_KEY"].present? ? 0.6.seconds : 6.seconds
    row = create_or_find_by!(name: NAME)

    row.with_lock do
      now = Time.current
      allowed_at = [ row.next_allowed_at || now, now ].max
      if allowed_at > now
        allowed_at
      else
        row.update!(next_allowed_at: now + interval)
        nil
      end
    end
  end
end
