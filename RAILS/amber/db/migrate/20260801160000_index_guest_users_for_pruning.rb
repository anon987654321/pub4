# frozen_string_literal: true

# Matches brgen: Shared::PruneGuestUsersJob scans users WHERE guest = 1 AND
# created_at <= ?, and amber carries the same guest column and the same
# unbounded row growth. The job is scheduled in config/recurring.yml.
class IndexGuestUsersForPruning < ActiveRecord::Migration[8.0]
  def change
    add_index :users, %i[guest created_at], name: "index_users_on_guest_and_created_at"
  end
end
