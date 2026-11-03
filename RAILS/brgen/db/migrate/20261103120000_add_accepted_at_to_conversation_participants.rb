# frozen_string_literal: true

# A message request: a DM from someone the recipient has never talked to and
# does not follow waits in Requests until it is accepted, instead of landing in
# the inbox, lighting the badge and pushing to a lock screen. The state is the
# recipient's own, so it sits on their participant row like pin, mute and
# archive; NULL is a request not yet accepted.
class AddAcceptedAtToConversationParticipants < ActiveRecord::Migration[8.1]
  def up
    add_column :conversation_participants, :accepted_at, :datetime
    # Every thread that exists today was already in someone's inbox. Accepted
    # as of when they joined it, so nothing moves into Requests on deploy.
    execute "UPDATE conversation_participants SET accepted_at = created_at"
    add_index :conversation_participants, %i[user_id accepted_at]
  end

  def down
    remove_index :conversation_participants, %i[user_id accepted_at]
    remove_column :conversation_participants, :accepted_at
  end
end
