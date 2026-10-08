# frozen_string_literal: true

module Tv
  class Show < ApplicationRecord
    tracks_activity created: "TvShowCreated", updated: "TvShowUpdated", source_vertical: "tv", actor: :channel_owner

    self.table_name = "tv_shows"

    belongs_to :channel, class_name: "Tv::Channel"
    has_many :episodes, class_name: "Tv::Episode", dependent: :destroy

    # slug is NOT NULL and the show routes by it, but RedditSeed and the x rake
    # task create shows from a title alone; deriving it is what lets them save.
    before_validation { self.slug = title.to_s.parameterize if slug.blank? }

    validates :title, :description, :slug, presence: true
    validates :slug, uniqueness: { scope: :channel_id }

    scope :published, -> { where(published: true) }

    def to_param
      slug
    end

  # tracks_activity actor — see Shared::StrictSafeAssociations.
  def channel_owner = strict_safe(:channel)&.user
  end
end
