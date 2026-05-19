# frozen_string_literal: true

class Community < ApplicationRecord
  belongs_to :user, optional: true

  has_many :posts, dependent: :destroy

  validates :name,        presence: true, uniqueness: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }

  POPULAR_SQL = Arel.sql("COUNT(posts.id) DESC")
  scope :popular, -> { left_joins(:posts).group(:id).order(POPULAR_SQL) }
end
