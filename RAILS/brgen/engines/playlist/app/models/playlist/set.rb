# frozen_string_literal: true

module Playlist
  class Set < ApplicationRecord
    self.table_name = "playlist_sets"

    PRIVACY_LEVELS = %w[public private unlisted].freeze

    tracks_activity created: "PlaylistSetCreated", source_vertical: "playlist", actor: :user
    include Shared::Reactable
    include Shared::Notifiable
    belongs_to :user
    has_many :set_tracks, class_name: "Playlist::SetTrack", foreign_key: :playlist_set_id, dependent: :destroy,
             inverse_of: :set
    has_many :tracks, through: :set_tracks, source: :track, class_name: "Playlist::Track"
    has_many :collaborations, class_name: "Playlist::Collaboration", dependent: :destroy
    has_many :collaborators, through: :collaborations, source: :user
    has_many :dilla_sketches, class_name: "Playlist::DillaSketch", dependent: :destroy
    has_many :likes, class_name: "Playlist::Like", dependent: :destroy
    has_one :listening_party, class_name: "Playlist::ListeningParty", foreign_key: :playlist_set_id,
            dependent: :destroy, inverse_of: :set

    validates :name, presence: true
    validates :privacy, inclusion: { in: PRIVACY_LEVELS }, allow_blank: true

    scope :visible, -> { where(privacy: [ nil, "public", "unlisted" ]) }
    scope :publicly_listed, -> { where(privacy: [ nil, "public" ]) }

    def add_track!(track, user:)
      set_track = set_tracks.find_or_initialize_by(track: track)
      return set_track if set_track.persisted?

      set_track.position = set_tracks.maximum(:position).to_i + 1
      set_track.user = user
      set_track.save!
      set_track
    end

    def total_duration
      tracks.sum(:duration_seconds).to_i
    end

    def formatted_duration
      seconds = total_duration
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      rest = seconds % 60
      hours.positive? ? format("%d:%02d:%02d", hours, minutes, rest) : format("%d:%02d", minutes, rest)
    end
  end
end
