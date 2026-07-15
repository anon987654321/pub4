# frozen_string_literal: true

# Backfills + adds NOT NULL constraints that already exist as `validates
# presence:` in the models but were never enforced at the DB layer, adds
# missing FK indexes, and deduplicates + adds unique indexes backing
# `validates uniqueness:` checks that were previously app-only (a real race
# under concurrent requests — e.g. two taps on "like" landing at once).
class AddIntegrityConstraints < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE comments SET content = '' WHERE content IS NULL"
    change_column_null :comments, :content, false

    execute "UPDATE communities SET name = 'Untitled community' WHERE name IS NULL"
    change_column_null :communities, :name, false

    # hashtags.name already carries a unique index — backfill with a
    # per-row-unique placeholder so the constraint doesn't collide.
    execute "UPDATE hashtags SET name = 'untitled-' || id WHERE name IS NULL"
    change_column_null :hashtags, :name, false

    execute "UPDATE messages SET content = '' WHERE content IS NULL"
    change_column_null :messages, :content, false

    execute "UPDATE posts SET title = 'Untitled post' WHERE title IS NULL"
    change_column_null :posts, :title, false

    add_index :comments, :parent_id unless index_exists?(:comments, :parent_id)
    add_index :communities, :user_id unless index_exists?(:communities, :user_id)
    add_index :marketplace_categories, :parent_id unless index_exists?(:marketplace_categories, :parent_id)
    add_index :marketplace_saved_searches, :category_id unless index_exists?(:marketplace_saved_searches, :category_id)
    add_index :messages, :sender_id unless index_exists?(:messages, :sender_id)

    dedup_and_unique_index :dating_dislikes, %i[disliker_id dislikee_id]
    dedup_and_unique_index :dating_likes, %i[liker_id likee_id]
    dedup_and_unique_index :dating_matches, %i[initiator_id receiver_id]
    dedup_and_unique_index :follows, %i[follower_id followed_id]
    dedup_and_unique_index :marketplace_categories, %i[slug]
    dedup_and_unique_index :playlist_playlist_tracks, %i[playlist_playlist_id playlist_track_id]
    dedup_and_unique_index :takeaway_reviews, %i[order_id user_id]
    dedup_and_unique_index :tv_channels, %i[slug]
    dedup_and_unique_index :tv_subscriptions, %i[user_id tv_channel_id]
    dedup_and_unique_index :votes, %i[user_id votable_type votable_id]

    rename_duplicate_usernames
    add_index :users, :username, unique: true unless index_exists?(:users, :username, unique: true)
  end

  def down
    remove_index :users, :username if index_exists?(:users, :username, unique: true)
    remove_index :votes, column: %i[user_id votable_type votable_id] if index_exists?(:votes, %i[user_id votable_type votable_id])
    remove_index :tv_subscriptions, column: %i[user_id tv_channel_id] if index_exists?(:tv_subscriptions, %i[user_id tv_channel_id])
    remove_index :tv_channels, :slug if index_exists?(:tv_channels, :slug)
    remove_index :takeaway_reviews, column: %i[order_id user_id] if index_exists?(:takeaway_reviews, %i[order_id user_id])
    remove_index :playlist_playlist_tracks, column: %i[playlist_playlist_id playlist_track_id] if index_exists?(:playlist_playlist_tracks, %i[playlist_playlist_id playlist_track_id])
    remove_index :marketplace_categories, :slug if index_exists?(:marketplace_categories, :slug)
    remove_index :follows, column: %i[follower_id followed_id] if index_exists?(:follows, %i[follower_id followed_id])
    remove_index :dating_matches, column: %i[initiator_id receiver_id] if index_exists?(:dating_matches, %i[initiator_id receiver_id])
    remove_index :dating_likes, column: %i[liker_id likee_id] if index_exists?(:dating_likes, %i[liker_id likee_id])
    remove_index :dating_dislikes, column: %i[disliker_id dislikee_id] if index_exists?(:dating_dislikes, %i[disliker_id dislikee_id])

    remove_index :messages, :sender_id if index_exists?(:messages, :sender_id)
    remove_index :marketplace_saved_searches, :category_id if index_exists?(:marketplace_saved_searches, :category_id)
    remove_index :marketplace_categories, :parent_id if index_exists?(:marketplace_categories, :parent_id)
    remove_index :communities, :user_id if index_exists?(:communities, :user_id)
    remove_index :comments, :parent_id if index_exists?(:comments, :parent_id)

    change_column_null :posts, :title, true
    change_column_null :messages, :content, true
    change_column_null :hashtags, :name, true
    change_column_null :communities, :name, true
    change_column_null :comments, :content, true
  end

  private

  # Keeps the earliest row for each duplicate key and deletes the rest —
  # these are rows that already violated the model's own `validates
  # uniqueness:` scope, so they represent duplicate data the app never
  # intended to allow, not real divergent user records.
  def dedup_and_unique_index(table, columns)
    return if index_exists?(table, columns, unique: true)

    cols = columns.join(", ")
    execute <<~SQL.squish
      DELETE FROM #{table}
      WHERE id NOT IN (
        SELECT MIN(id) FROM #{table} GROUP BY #{cols}
      )
    SQL
    add_index table, columns, unique: true
  end

  # Real user accounts, unlike join-table rows, must never be deleted to
  # resolve a uniqueness conflict — rename the later duplicate instead so a
  # human can sort out which one is canonical.
  def rename_duplicate_usernames
    dupes = select_rows(<<~SQL.squish)
      SELECT id, username FROM users
      WHERE username IS NOT NULL
        AND username IN (
          SELECT username FROM users WHERE username IS NOT NULL GROUP BY username HAVING COUNT(*) > 1
        )
      ORDER BY username, id
    SQL

    dupes.group_by { |(_id, username)| username }.each_value do |rows|
      rows.drop(1).each do |(id, username)|
        execute "UPDATE users SET username = #{quote("#{username}-dup#{id}")} WHERE id = #{id}"
      end
    end
  end
end
