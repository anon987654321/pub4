# frozen_string_literal: true

# Classifieds expire. Without it a marketplace fills with things sold two years
# ago that nobody bothered to take down, and the honest listings drown in them —
# which is the failure mode every classifieds site is built to avoid.
#
# Renewal rather than deletion, because a seller who still has the thing should
# not have to retype it, and a listing that quietly vanished would look like a
# bug rather than a policy.
class AddListingExpiry < ActiveRecord::Migration[8.1]
  def change
    change_table :marketplace_listings, bulk: true do |t|
      t.datetime :expires_at
      t.datetime :renewal_notice_sent_at
    end

    # The scope every listing surface reads: still live.
    add_index :marketplace_listings, %i[status expires_at]

    reversible do |dir|
      dir.up do
        # Existing listings get a full window from now rather than from their
        # creation date — backdating would expire the whole marketplace on the
        # first sweep.
        execute "UPDATE marketplace_listings SET expires_at = datetime('now', '+45 days') WHERE expires_at IS NULL"
      end
    end
  end
end
