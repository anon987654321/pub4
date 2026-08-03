# frozen_string_literal: true

class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  # normalizes unifies write-side and lookup normalization (find_by(name:) too),
  # so #foo, #FOO and #Foo! all resolve to the one "foo" tag.
  normalizes :name, with: ->(name) { name.to_s.downcase.gsub(/[^a-z0-9_]/, "") }

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  scope :trending, -> { order(usage_count: :desc) }

  def self.extract(text)
    text.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.map(&:downcase).uniq
  end
end
