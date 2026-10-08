# frozen_string_literal: true

# Three things a messenger is expected to do that this one could not.
#
# Reply-to: in a channel with several conversations running at once, a message
# with no referent is a message nobody can follow.
#
# Edit and unsend: a typo currently stands forever, and a message sent to the
# wrong room cannot be taken back — which on a hyperlocal chat with real
# addresses in it is a safety gap, not a convenience one.
#
# Voice: a has_one_attached already exists for images, and a voice note is the
# same attachment with a different content type.
class AddMessageRepliesAndEdits < ActiveRecord::Migration[8.1]
  def change
    change_table :messages, bulk: true do |t|
      t.references :parent, foreign_key: { to_table: :messages }
      t.datetime :edited_at
      # Soft, not a delete: a hard delete leaves a hole in a threaded
      # conversation and orphans anything that replied to it. The row stays and
      # the body goes.
      t.datetime :deleted_at
      t.integer :duration_seconds
    end

    add_index :messages, :parent_id unless index_exists?(:messages, :parent_id)
    # The scope every conversation render uses: what is still here.
    add_index :messages, %i[conversation_id deleted_at]
  end
end
