# frozen_string_literal: true

module Playlist
  class Like < ApplicationRecord
    self.table_name = "playlist_likes"

    include Shared::ActivityTrackable
    tracks_activity created: "PlaylistLiked", source_vertical: "playlist", visibility: "private", actor: :user

    belongs_to :user
    belongs_to :set, class_name: "Playlist::Set", optional: true
    belongs_to :playlist, class_name: "Playlist::Playlist", optional: true

    validates :user_id, uniqueness: { scope: %i[set_id playlist_id] }
    validate :target_present

    private

    def target_present
      errors.add(:base, "playlist target required") if set_id.blank? && playlist_id.blank?
    end
  end
end
