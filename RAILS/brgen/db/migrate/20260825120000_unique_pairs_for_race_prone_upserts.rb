# frozen_string_literal: true

# Three `find_or_create_by` calls whose uniqueness was written nowhere.
#
# `find_or_create_by` is a read followed by a write. Under Falcon two requests
# interleave between the two halves and both write, and the only thing that can
# stop them is a constraint in the database — a model validation reads the same
# stale row the finder did.
#
#   conversation_participants  Conversation#join!    the worst of the three:
#     `last_read_at` lives on this row, so a duplicate splits the read watermark.
#     One row gets updated when the thread is opened and the unread query reads
#     the other, so the badge never goes to zero and re-opening cannot clear it.
#
#   trust_signals              ModerationWorkflow#penalize_owner
#     TrustScore sums these rows. A duplicate signal is a duplicate penalty, so
#     a retried job moves someone's reputation twice for one report.
#
#   typing_indicators          TypingIndicator.set!
#     The highest-frequency write in the app, and the likeliest of the three to
#     actually race. It self-heals when the row expires, which is why nobody
#     saw it.
#
# The merge before each index matters: dropping the newer row would throw away
# the read watermark, the pin and the IRC mode, which is the data the duplicate
# was hiding. Every surviving row keeps the strongest value of each.
class UniquePairsForRaceProneUpserts < ActiveRecord::Migration[8.1]
  def up
    merge_duplicate_participants
    add_index :conversation_participants, %i[conversation_id user_id],
              unique: true, name: "index_conversation_participants_on_pair"

    dedupe_trust_signals
    add_index :trust_signals, %i[user_id kind source],
              unique: true, name: "index_trust_signals_on_user_kind_source"

    dedupe_typing_indicators
    add_index :typing_indicators, %i[conversation_id user_id],
              unique: true, name: "index_typing_indicators_on_pair"
  end

  def down
    remove_index :conversation_participants, name: "index_conversation_participants_on_pair"
    remove_index :trust_signals, name: "index_trust_signals_on_user_kind_source"
    remove_index :typing_indicators, name: "index_typing_indicators_on_pair"
  end

  private

  # Fold every duplicate's state into the row that survives, then delete the
  # rest. `role` only ever rises (same rule as Conversation#join!), and both
  # timestamps take the later of the two.
  def merge_duplicate_participants
    execute(<<~SQL.squish)
      UPDATE conversation_participants AS keep SET
        last_read_at = (SELECT MAX(d.last_read_at) FROM conversation_participants d
                        WHERE d.conversation_id = keep.conversation_id AND d.user_id = keep.user_id),
        pinned_at = (SELECT MAX(d.pinned_at) FROM conversation_participants d
                        WHERE d.conversation_id = keep.conversation_id AND d.user_id = keep.user_id),
        role = (SELECT CASE MAX(CASE d.role WHEN 'op' THEN 2 WHEN 'voice' THEN 1 ELSE 0 END)
                                 WHEN 2 THEN 'op' WHEN 1 THEN 'voice' ELSE 'member' END
                        FROM conversation_participants d
                        WHERE d.conversation_id = keep.conversation_id AND d.user_id = keep.user_id)
      WHERE EXISTS (SELECT 1 FROM conversation_participants d
                    WHERE d.conversation_id = keep.conversation_id
                      AND d.user_id = keep.user_id AND d.id <> keep.id)
    SQL

    execute(<<~SQL.squish)
      DELETE FROM conversation_participants WHERE id NOT IN (
        SELECT MIN(id) FROM conversation_participants GROUP BY conversation_id, user_id
      )
    SQL
  end

  # Nothing to merge: a duplicate signal is the double-count itself, and every
  # column on the loser is a copy of the winner's.
  def dedupe_trust_signals
    execute(<<~SQL.squish)
      DELETE FROM trust_signals WHERE id NOT IN (
        SELECT MIN(id) FROM trust_signals GROUP BY user_id, kind, source
      )
    SQL
  end

  # Keep the furthest expiry, or a live indicator becomes a dead one.
  def dedupe_typing_indicators
    execute(<<~SQL.squish)
      UPDATE typing_indicators AS keep SET
        expires_at = (SELECT MAX(d.expires_at) FROM typing_indicators d
                      WHERE d.conversation_id = keep.conversation_id AND d.user_id = keep.user_id)
      WHERE EXISTS (SELECT 1 FROM typing_indicators d
                    WHERE d.conversation_id = keep.conversation_id
                      AND d.user_id = keep.user_id AND d.id <> keep.id)
    SQL

    execute(<<~SQL.squish)
      DELETE FROM typing_indicators WHERE id NOT IN (
        SELECT MIN(id) FROM typing_indicators GROUP BY conversation_id, user_id
      )
    SQL
  end
end
