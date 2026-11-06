# frozen_string_literal: true

class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  # normalizes unifies write-side and lookup normalization (find_by(name:) too),
  # so #foo, #FOO and #Foo! all resolve to the one "foo" tag.
  normalizes :name, with: ->(name) { name.to_s.downcase.gsub(/[^a-z0-9_]/, "") }

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  # Trending means "used a lot lately", not "used a lot ever" — rank by taggings in
  # the last week so a burst of activity surfaces and stale all-time leaders fade.
  # taggable_type is unfiltered on purpose: a tag hot across posts and videos alike
  # is exactly what "trending" should reward.
  TRENDING_WINDOW = 7.days
  scope :trending, -> {
    joins(:taggings)
      .where(taggings: { created_at: TRENDING_WINDOW.ago.. })
      .group(:id)
      .order(Arel.sql("COUNT(taggings.id) DESC"))
  }

  def self.extract(text)
    text.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.map(&:downcase).uniq
  end
end
