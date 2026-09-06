# frozen_string_literal: true

# `streams` was the pre-Active-Storage way to hang a media file off a post: a
# url, a content type and a duration. It was created 2026-03-11 at 16:22:35, ten
# minutes before `posts` existed, and nothing has ever written a row — no
# reader, no writer, no seed, in the app or either sibling.
#
# Three models took the job it was created for, and each does it better:
#
#   Post has_one_attached :image/:video/:audio, with Shared::MediaProcessable
#     variants — uploaded media, with the storage and moderation story attached.
#   Playlist::Track, whose SOURCE_TYPES are upload/youtube/spotify/soundcloud/
#     whyp/direct/dilla — audio hosted elsewhere, with listens, timestamped
#     comments and audio versions.
#   LinkPreview, for a pasted URL, deliberately without an image for the privacy
#     reason its own comment states.
#
# Live video is Tv::LiveStream (stream_key, status, viewer_count) with
# Tv::StreamChat beside it. Keeping `streams` meant a second, weaker media path
# beside Active Storage and a second external-URL model beside Playlist::Track,
# which is what ONE_SOURCE exists to stop.
#
# Reversible: the block restores the table as it stood, so a rollback gets the
# schema back. The rows are not restorable, and there are none.
class DropStreams < ActiveRecord::Migration[8.1]
  def change
    drop_table :streams do |t|
      t.string :content_type
      t.string :url
      t.references :user, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true
      t.integer :duration

      t.timestamps
    end
  end
end
