# frozen_string_literal: true

module Playlist
  class Collaboration < ApplicationRecord
    self.table_name = "playlist_collaborations"

    include Shared::ActivityTrackable
    tracks_activity created: "PlaylistCollaborationCreated", source_vertical: "playlist", visibility: "private", actor: :user

    ROLES = %w[owner editor viewer].freeze

    belongs_to :user
    belongs_to :set, class_name: "Playlist::Set", optional: true
    belongs_to :playlist, class_name: "Playlist::Playlist", optional: true

    validates :role, inclusion: { in: ROLES }, allow_blank: true
    validates :user_id, uniqueness: { scope: %i[set_id playlist_id] }

    before_validation :default_role

    private

    def default_role
      self.role = "editor" if role.blank?
    end
  end
end
