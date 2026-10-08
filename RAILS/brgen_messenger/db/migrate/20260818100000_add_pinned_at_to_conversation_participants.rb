# frozen_string_literal: true

# Pinning is one person's ordering of their own inbox, so the column sits on the
# participant row rather than the conversation: a pin on the shared record would
# let either side of a DM reorder the other's list.
class AddPinnedAtToConversationParticipants < ActiveRecord::Migration[8.1]
  def change
    # A timestamp, not a boolean — pinned threads order among themselves by when
    # they were pinned, and a boolean cannot say which pin is newer.
    add_column :conversation_participants, :pinned_at, :datetime

    # The messenger list orders on this column for one user at a time.
    add_index :conversation_participants, %i[user_id pinned_at]
  end
end
