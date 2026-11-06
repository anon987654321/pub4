# frozen_string_literal: true

# Shared::PruneGuestUsersJob scans users WHERE guest = 1 AND created_at <= ?,
# and until now that was a full table scan over a table that was 99.3% throwaway
# guest rows (102,778 of them measured on 2026-08-01). The job was also never
# scheduled, so nothing paid the cost — both halves are fixed together, and the
# index has to exist before the schedule turns on.
class IndexGuestUsersForPruning < ActiveRecord::Migration[8.0]
  def change
    add_index :users, %i[guest created_at], name: "index_users_on_guest_and_created_at"
  end
end
