# frozen_string_literal: true

# Every hot message read bounds by time inside one thread: the window and
# history pages (ORDER BY created_at DESC LIMIT 51), the per-thread
# MAX(created_at) behind the inbox ordering, the channel active counts and
# the unread badge's created_at range. (conversation_id, deleted_at) served
# the filter; the sort then walked everything the thread ever held. The
# composite serves filter and sort at once, newest first.
class AddMessagesConversationCreatedAtIndex < ActiveRecord::Migration[8.2]
  def change
    add_index :messages, %i[conversation_id created_at],
              name: "index_messages_on_conversation_id_and_created_at"
  end
end
