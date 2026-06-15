# frozen_string_literal: true

module Playlist
  class Set < ApplicationRecord
    self.table_name = "playlist_sets"

    PRIVACY_LEVELS = %w[public private unlisted].freeze

    belongs_to :user
    has_many :set_tracks, class_name: "Playlist::SetTrack", foreign_key: :playlist_set_id, dependent: :destroy
    has_many :tracks, through: :set_tracks, source: :track
    has_many :collaborations, class_name: "Playlist::Collaboration", dependent: :destroy
    has_many :collaborators, through: :collaborations, source: :user
    has_many :dilla_sketches, class_name: "Playlist::DillaSketch", dependent: :destroy
    has_many :likes, class_name: "Playlist::Like", dependent: :destroy

    validates :name, presence: true
    validates :privacy, inclusion: { in: PRIVACY_LEVELS }, allow_blank: true

    scope :visible, -> { where(privacy: [nil, "public", "unlisted"]) }
    scope :publicly_listed, -> { where(privacy: [nil, "public"]) }
    scope :search, ->(q) {
      term = q.to_s.strip
      return none if term.empty?

      ids = connection.select_values(
        sanitize_sql_array(["SELECT rowid FROM playlist_sets_fts WHERE playlist_sets_fts MATCH ?", term])
      )
      ids.any? ? where(id: ids) : none
    }
    scope :with_track_facets, ->(genre: nil, artist: nil) {
      scope = all
      scope = scope.joins(set_tracks: :track).where(playlist_tracks: { genre: genre }) if genre.present?
      scope = scope.joins(set_tracks: :track).where(playlist_tracks: { artist: artist }) if artist.present?
      scope.distinct
    }

    def total_duration
      tracks.sum(:duration).to_i
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
