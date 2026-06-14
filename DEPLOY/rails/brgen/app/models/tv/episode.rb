# frozen_string_literal: true

module Tv
  class Episode < ApplicationRecord
    self.table_name = "tv_episodes"

    belongs_to :show, class_name: "Tv::Show"
    belongs_to :video, class_name: "Tv::Video", optional: true

    validates :title, :number, presence: true
    validates :number, uniqueness: { scope: :show_id }

    def to_param
      number.to_s
    end
  end
end
