# frozen_string_literal: true

module Tv
  class Episode < ApplicationRecord
    # Engine-ize Shared via pub4-shared
    tracks_activity created: "TvEpisodeCreated", updated: "TvEpisodeUpdated", source_vertical: "tv", actor: :channel_owner
    include Shared::Reactable
    include Shared::Notifiable

    self.table_name = "tv_episodes"

    belongs_to :show, class_name: "Tv::Show"
    belongs_to :video, class_name: "Tv::Video", optional: true

    validates :title, :number, presence: true
    validates :number, uniqueness: { scope: :show_id }

    def to_param
      number.to_s
    end

  # tracks_activity actor. Two hops, so the intermediate show is fetched without
  # strict loading and can then be walked normally.
  # See Shared::StrictSafeAssociations.
  def channel_owner = strict_safe(:show)&.channel&.user
  end
end
