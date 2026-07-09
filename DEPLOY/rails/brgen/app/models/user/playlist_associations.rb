# frozen_string_literal: true

class User
  module PlaylistAssociations
    extend ActiveSupport::Concern

    included do
      has_many :playlist_listens, class_name: "Playlist::Listen", dependent: :destroy
      has_many :playlist_playlists, class_name: "Playlist::Playlist", dependent: :destroy
    end
  end
end