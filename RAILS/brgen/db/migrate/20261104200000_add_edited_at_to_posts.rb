# frozen_string_literal: true

# When the author last changed what a post says, so cards and the post page
# can mark it edited, as messages do with their own edited_at.
class AddEditedAtToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :edited_at, :datetime
  end
end
