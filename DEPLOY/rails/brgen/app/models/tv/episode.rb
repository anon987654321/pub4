# frozen_string_literal: true

module Tv
  class Episode < ApplicationRecord
    # Engine-ize Shared via pub4-shared
    include Shared.concern(:ActivityTrackable) rescue include Shared::ActivityTrackable
    tracks_activity created: "TvEpisodeCreated", updated: "TvEpisodeUpdated", source_vertical: "tv", actor: :channel_owner
    include Shared.concern(:Reactable) rescue nil
    include Shared.concern(:Notifiable) rescue nil

    self.table_name = "tv_episodes"

    belongs_to :show, class_name: "Tv::Show"
    belongs_to :video, class_name: "Tv::Video", optional: true

    validates :title, :number, presence: true
    validates :number, uniqueness: { scope: :show_id }

    def to_param
      number.to_s
    end

    def channel_owner = show&.channel&.user
  end
end
