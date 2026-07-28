# frozen_string_literal: true

# Post#comment_count called comments.count on every render — 50 of the home
# page's 243 queries, two per feed post. A counter cache answers it from the row
# the post is already loaded with.
class AddCommentsCountToPosts < ActiveRecord::Migration[8.1]
  def up
    add_column :posts, :comments_count, :integer, default: 0, null: false

    # Backfill in one statement rather than N reset_counters calls.
    execute <<~SQL.squish
      UPDATE posts SET comments_count = (
        SELECT COUNT(*) FROM comments
        WHERE comments.commentable_id = posts.id
          AND comments.commentable_type = 'Post'
      )
    SQL
  end

  def down
    remove_column :posts, :comments_count
  end
end
