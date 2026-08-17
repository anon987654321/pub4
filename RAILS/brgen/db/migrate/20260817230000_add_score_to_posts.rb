# frozen_string_literal: true

# posts.score, so ranking a feed does not aggregate the votes table.
#
# `hot` and `top` were LEFT JOIN votes + GROUP BY posts.id + SUM(votes.value),
# which is O(posts x votes) every time the front page is drawn. Measured before
# this on 295 posts and 120 votes: hot 6.1ms against fresh 0.6ms for the same 25
# rows. Ten times the cost at a size where the absolute number is still small,
# which is the moment to fix it rather than the moment it hurts.
#
# Posts only. Shared::Votable is included by Comment and Takeaway::Review as
# well, and neither ranks by score — they read it one record at a time, where the
# aggregate is one cheap query. The concern prefers the column when a table has
# one and falls back to the sum when it does not, so this stays a per-table
# decision instead of a migration across every votable.
class AddScoreToPosts < ActiveRecord::Migration[8.1]
  def up
    add_column :posts, :score, :integer, default: 0, null: false

    # The index is the point: ORDER BY posts.score has nothing to sort on
    # otherwise. Paired with created_at because both scopes tie-break on it.
    add_index :posts, [ :score, :created_at ]

    # Backfill before anything reads the column, in one statement rather than a
    # find_each — 295 rows today, and a row-at-a-time backfill is a habit that
    # stops working at the size where it matters.
    execute <<~SQL.squish
      UPDATE posts SET score = COALESCE((
        SELECT SUM(votes.value) FROM votes
        WHERE votes.votable_type = 'Post' AND votes.votable_id = posts.id
      ), 0)
    SQL
  end

  def down
    remove_index :posts, [ :score, :created_at ]
    remove_column :posts, :score
  end
end
