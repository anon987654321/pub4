# frozen_string_literal: true

class PlaylistTimestampedCommentsReflex < ApplicationReflex
  def create
    params = element.dataset
    track = Playlist::Track.find(params.track_id || params["track-id"])
    return unless track

    comment = track.timestamped_comments.build(
      user: Current.user,
      body: params.body || params["body"],
      timestamp_seconds: (params.timestamp || params["timestamp"]).to_f
    )

    if comment.save
      # broadcast handled in model after_create
      morph :nothing
    else
      # handle error, perhaps cable
    end
  end
end
