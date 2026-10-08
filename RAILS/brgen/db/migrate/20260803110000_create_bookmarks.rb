# frozen_string_literal: true

# Save a post to read later. A private per-user list — no counts exposed, no
# notification to the author.
class CreateBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true
      t.timestamps
    end
    add_index :bookmarks, %i[user_id post_id], unique: true
  end
end
