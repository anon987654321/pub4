# frozen_string_literal: true

class Tv::Comment < ApplicationRecord
  belongs_to :user
  belongs_to :video, class_name: "Tv::Video"

  validates :body, presence: true, length: { maximum: 1_000 }
end
