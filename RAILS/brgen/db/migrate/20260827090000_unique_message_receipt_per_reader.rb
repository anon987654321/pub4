# frozen_string_literal: true

# One receipt per reader per message, enforced.
#
# mark_read_for! used find_or_initialize_by, which is a read-then-write with a gap
# in the middle: two tabs opening the same room at once each find nothing and each
# insert, and the pair then disagree about when the message was first read. The
# same shape was fixed for conversation_participants and trust_signals in
# 20260825120000; this is the third table with it.
#
# The duplicate merge is guarded, and the guard is the point. The first version of
# this migration ran two correlated subqueries over every row unconditionally —
# and the pair it correlates on is exactly the pair this migration is adding an
# index for, so each one was a full scan. Measured on vm23 before deploying:
# 38,201 receipts and zero duplicate pairs, so that work would have scanned
# roughly three billion rows on one vCPU to change nothing. The GROUP BY that
# proves there is nothing to do takes 0.9s.
class UniqueMessageReceiptPerReader < ActiveRecord::Migration[8.0]
  def up
    if duplicates?
      say_with_time "merging duplicate message receipts" do
        # Keep the earliest read_at and delivered_at: the first time something was
        # read is the fact worth preserving. Correlated on id, which is the primary
        # key, rather than on the unindexed pair.
        execute <<~SQL
          CREATE TEMP TABLE receipt_merge AS
            SELECT MIN(id) AS keep_id,
                   MIN(read_at) AS first_read_at,
                   MIN(delivered_at) AS first_delivered_at
            FROM message_receipts
            GROUP BY message_id, user_id
        SQL
        execute <<~SQL
          UPDATE message_receipts SET
            read_at = (SELECT first_read_at FROM receipt_merge m WHERE m.keep_id = message_receipts.id),
            delivered_at = (SELECT first_delivered_at FROM receipt_merge m WHERE m.keep_id = message_receipts.id)
          WHERE id IN (SELECT keep_id FROM receipt_merge)
        SQL
        execute "DELETE FROM message_receipts WHERE id NOT IN (SELECT keep_id FROM receipt_merge)"
        execute "DROP TABLE receipt_merge"
      end
    else
      say "no duplicate message receipts — skipping the merge"
    end

    add_index :message_receipts, %i[message_id user_id], unique: true,
              name: "index_message_receipts_on_message_and_user"
  end

  def down
    remove_index :message_receipts, name: "index_message_receipts_on_message_and_user"
  end

  private

  def duplicates?
    select_value(<<~SQL).to_i.positive?
      SELECT COUNT(*) FROM (
        SELECT message_id, user_id FROM message_receipts
        GROUP BY message_id, user_id HAVING COUNT(*) > 1
      )
    SQL
  end
end
