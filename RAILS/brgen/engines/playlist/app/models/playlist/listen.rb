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
    track.playlists.each { |pl| pl.increment!(:plays_count) }
  end
end
