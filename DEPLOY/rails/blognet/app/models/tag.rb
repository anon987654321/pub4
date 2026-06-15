# frozen_string_literal: true

class Tag < ApplicationRecord
  has_many :taggings, dependent: :destroy
  has_many :posts, through: :taggings

  validates :name, presence: true, uniqueness: true

  before_validation -> { self.name = name.to_s.strip.downcase }, on: :create

  scope :popular, -> { where("posts_count > 0").order(posts_count: :desc) }
end
