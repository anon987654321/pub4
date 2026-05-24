# frozen_string_literal: true

module Playlist
  class Set < ApplicationRecord
    self.table_name = "playlist_sets"

    PRIVACY_LEVELS = %w[public private unlisted].freeze

    belongs_to :user
    has_many :tracks, -> { order(:position) }, class_name: "Playlist::Track", dependent: :destroy
    has_many :collaborations, class_name: "Playlist::Collaboration", dependent: :destroy
    has_many :collaborators, through: :collaborations, source: :user
    has_many :likes, class_name: "Playlist::Like", dependent: :destroy

    validates :name, presence: true
    validates :privacy, inclusion: { in: PRIVACY_LEVELS }, allow_blank: true

    scope :visible, -> { where(privacy: [nil, "public", "unlisted"]) }
    scope :publicly_listed, -> { where(privacy: [nil, "public"]) }

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
