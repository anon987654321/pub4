# frozen_string_literal: true

# Two reputation stores become one.
#
# `users.karma` was recomputed on every vote and rendered by nothing — the name
# appeared in no view, helper or partial in any app or engine. `posts.karma` was
# read by nothing at all; `posts.score` is the live column. Meanwhile
# `reputation_scores` is wired and tested: unique per (user, scope), written by
# TrustScore as scope "global".
#
# So the value moves rather than dies. Every non-zero karma is written as a
# `content` row first, and only then are the columns dropped — a person's score
# survives the collapse, in the store that is actually read.
#
# down restores the columns and the users half from the rows, because that is
# what a reversible migration owes. posts.karma cannot be restored and does not
# need to be: nothing ever wrote it.
class FoldKarmaIntoReputationScores < ActiveRecord::Migration[8.0]
  def up
    now = Time.current
    rows = execute("SELECT id, karma FROM users WHERE karma IS NOT NULL AND karma != 0").to_a

    rows.each do |row|
      user_id = row.is_a?(Hash) ? row["id"] : row[0]
      karma = row.is_a?(Hash) ? row["karma"] : row[1]
      execute(<<~SQL.squish)
        INSERT INTO reputation_scores (user_id, scope, score, calculated_at, created_at, updated_at)
        VALUES (#{user_id.to_i}, 'content', #{karma.to_i}, '#{now.utc.iso8601}', '#{now.utc.iso8601}', '#{now.utc.iso8601}')
        ON CONFLICT (user_id, scope) DO UPDATE SET score = excluded.score, calculated_at = excluded.calculated_at
      SQL
    end

    say "folded #{rows.size} karma value(s) into reputation_scores scope=content"

    remove_column :users, :karma
    remove_column :posts, :karma
  end

  def down
    add_column :users, :karma, :integer
    add_column :posts, :karma, :integer
    execute(<<~SQL.squish)
      UPDATE users SET karma = (
        SELECT score FROM reputation_scores
        WHERE reputation_scores.user_id = users.id AND reputation_scores.scope = 'content'
      )
    SQL
  end
end
