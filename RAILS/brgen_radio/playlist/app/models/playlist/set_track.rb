# frozen_string_literal: true

module Playlist
  class SetTrack < ApplicationRecord
    self.table_name = "playlist_set_tracks"

    belongs_to :set, class_name: "Playlist::Set", foreign_key: :playlist_set_id, inverse_of: :set_tracks
    # model_contract: no-inverse-ok — a Track does not collect the sets it
    # appears in; the reading direction is set to tracks, never back.
    belongs_to :track, class_name: "Playlist::Track", foreign_key: :playlist_track_id
    belongs_to :user

    validates :playlist_set_id, uniqueness: { scope: :playlist_track_id }

    default_scope { order(:position) }
  end
end
