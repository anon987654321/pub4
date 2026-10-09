# frozen_string_literal: true

# Mute and archive are one person's handling of their own inbox, so like the pin
# they sit on the participant row: a mute on the shared conversation would
# silence the other side too.
class AddMuteAndArchiveToConversationParticipants < ActiveRecord::Migration[8.1]
  def change
    # Timestamps rather than booleans, for the reason pinned_at is one: when a
    # thread was archived is a fact the list can show, and a boolean forgets it.
    add_column :conversation_participants, :muted_at, :datetime
    add_column :conversation_participants, :archived_at, :datetime

    # The list and the badge both filter one user's rows by archive state.
    add_index :conversation_participants, %i[user_id archived_at]
  end
end
