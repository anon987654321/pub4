# frozen_string_literal: true

class PlaylistTimestampedCommentsReflex < ApplicationReflex
  # The player sends the comment as the reflex's argument
  # (stimulate("PlaylistTimestampedComments#create", { track_id:, body:, timestamp: })).
  # The element is the player itself, whose dataset carries none of these, so
  # reading element.dataset found no track and no comment was ever saved.
  def create(comment = {})
    return unless Current.user

    comment = comment.to_h.stringify_keys
    track = Playlist::Track.find_by(id: comment["track_id"])
    return unless track&.visible_to?(Current.user)

    saved = track.timestamped_comments.build(
      user: Current.user,
      body: comment["body"].to_s.strip,
      timestamp_seconds: comment["timestamp"].to_f
    )
    morph :nothing if saved.save
  end
end
