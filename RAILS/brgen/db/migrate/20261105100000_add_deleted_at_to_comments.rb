# frozen_string_literal: true

# When the author deleted a comment that others had already answered. The row
# stays as a tombstone so the replies keep their place in the thread.
class AddDeletedAtToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :deleted_at, :datetime
  end
end
