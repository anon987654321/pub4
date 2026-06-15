# frozen_string_literal: true

module Tv
  class Show < ApplicationRecord
    include Shared::ActivityTrackable

    self.table_name = "tv_shows"

    belongs_to :channel, class_name: "Tv::Channel"
    has_many :episodes, class_name: "Tv::Episode", dependent: :destroy

    validates :title, :description, presence: true
    validates :slug, uniqueness: { scope: :channel_id }

    scope :published, -> { where(published: true) }

    def to_param
      slug
    end
  end
end
