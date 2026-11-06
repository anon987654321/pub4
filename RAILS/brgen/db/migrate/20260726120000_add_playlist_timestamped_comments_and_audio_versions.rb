# frozen_string_literal: true

# Playlist::TimestampedComment and Playlist::AudioVersion shipped as fully
# written models — validations, scopes, a broadcast callback, a StimulusReflex
# and player JS — but their migration was never authored. Every /playlists/:id
# render hit Track#timestamped_comments and raised "no such table", and
# Track#replace_audio! could not record a prior version.
#
# Columns are derived from the models and their call sites:
#   body / timestamp_seconds        — timestamped_comment.rb validations
#   original_filename / byte_size   — track.rb#replace_audio!
class AddPlaylistTimestampedCommentsAndAudioVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_timestamped_comments do |t|
      t.integer :track_id, null: false
      t.integer :user_id, null: false
      t.text :body, null: false
      # Nullable: the model allows nil (allow_nil) for comments not pinned to
      # a position. Float, because the reflex sends `.to_f` of a media time.
      t.float :timestamp_seconds
      t.timestamps
    end

    add_index :playlist_timestamped_comments, :track_id
    add_index :playlist_timestamped_comments, :user_id
    # Backs Playlist::TimestampedComment.chronological.
    add_index :playlist_timestamped_comments, %i[track_id timestamp_seconds created_at],
              name: "index_playlist_timestamped_comments_chronological"

    create_table :playlist_audio_versions do |t|
      t.integer :track_id, null: false
      # Nullable: belongs_to :user, optional: true — replace_audio! may run
      # with no actor (system/import path).
      t.integer :user_id
      t.string :original_filename, limit: 255
      t.bigint :byte_size
      t.timestamps
    end

    add_index :playlist_audio_versions, :track_id
    add_index :playlist_audio_versions, :user_id

    add_foreign_key :playlist_timestamped_comments, :playlist_tracks, column: :track_id
    add_foreign_key :playlist_timestamped_comments, :users
    add_foreign_key :playlist_audio_versions, :playlist_tracks, column: :track_id
    add_foreign_key :playlist_audio_versions, :users
  end
end
