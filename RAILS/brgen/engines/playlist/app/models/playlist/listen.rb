# frozen_string_literal: true

# model_contract: no-validations-ok — an append-only play event. Both foreign
# keys are required by the database and there is nothing else to promise.
class Playlist::Listen < ApplicationRecord
  # Engine-ized Shared (tranche10)
  tracks_activity created: "PlaylistListen", source_vertical: "playlist", visibility: "private", actor: :user
  include Shared::Reactable

  belongs_to :user
  belongs_to :track, class_name: "Playlist::Track", foreign_key: :playlist_track_id, inverse_of: :listens

  after_create :increment_plays

  private
  def increment_plays
    # One UPDATE across every playlist holding the track. update_counters reads
    # a NULL counter as zero and needs no loaded association.
    ::Playlist::Playlist.where(id: ::Playlist::PlaylistTrack.where(playlist_track_id: playlist_track_id).select(:playlist_playlist_id))
                        .update_counters(plays_count: 1)
  end
end
