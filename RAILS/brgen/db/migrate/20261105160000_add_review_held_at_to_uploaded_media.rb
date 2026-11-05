# frozen_string_literal: true

# A tv video or hosted track reported for copyright, abuse or illegal content
# is held out of public view until a moderator decides. Null means not held.
class AddReviewHeldAtToUploadedMedia < ActiveRecord::Migration[8.1]
  def change
    add_column :tv_videos, :review_held_at, :datetime
    add_column :playlist_tracks, :review_held_at, :datetime
  end
end
