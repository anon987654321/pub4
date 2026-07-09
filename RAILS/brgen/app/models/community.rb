# frozen_string_literal: true

class Community < ApplicationRecord
  include CityTenantable

  belongs_to :user, optional: true

  has_many :posts, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, uniqueness: { scope: :city_id }, allow_nil: true
  validates :description, length: { maximum: 500 }

  POPULAR_SQL = Arel.sql("COUNT(posts.id) DESC")
  scope :popular, -> { left_joins(:posts).group(:id).order(POPULAR_SQL) }
end
