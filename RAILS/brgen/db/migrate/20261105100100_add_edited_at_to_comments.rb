# frozen_string_literal: true

# When the author last changed what a comment says, so the thread can mark it
# edited, as posts and messages do with their own edited_at.
class AddEditedAtToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :edited_at, :datetime
  end
end
