# frozen_string_literal: true

# One receipt per reader per message, enforced.
#
# mark_read_for! used find_or_initialize_by, which is a read-then-write with a gap
# in the middle: two tabs opening the same room at once each find nothing and each
# insert, and the pair then disagree about when the message was first read. The
# same shape was fixed for conversation_participants and trust_signals in
# 20260825120000; this is the third table with it.
#
# Duplicates are merged rather than dropped, keeping the earliest read_at and
# delivered_at — the first time something was read is the fact worth preserving.
class UniqueMessageReceiptPerReader < ActiveRecord::Migration[8.0]
  def up
    say_with_time "merging duplicate message receipts" do
      execute <<~SQL
        UPDATE message_receipts SET
          read_at = (SELECT MIN(r2.read_at) FROM message_receipts r2
                     WHERE r2.message_id = message_receipts.message_id
                       AND r2.user_id = message_receipts.user_id
                       AND r2.read_at IS NOT NULL),
          delivered_at = (SELECT MIN(r2.delivered_at) FROM message_receipts r2
                          WHERE r2.message_id = message_receipts.message_id
                            AND r2.user_id = message_receipts.user_id
                            AND r2.delivered_at IS NOT NULL)
      SQL
      execute <<~SQL
        DELETE FROM message_receipts WHERE id NOT IN (
          SELECT MIN(id) FROM message_receipts GROUP BY message_id, user_id
        )
      SQL
    end

    add_index :message_receipts, %i[message_id user_id], unique: true,
              name: "index_message_receipts_on_message_and_user"
  end

  def down
    remove_index :message_receipts, name: "index_message_receipts_on_message_and_user"
  end
end
