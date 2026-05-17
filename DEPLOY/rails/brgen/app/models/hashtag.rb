class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.name = name.to_s.downcase.gsub(/[^a-z0-9_]/, "") }

  scope :trending, -> { order(usage_count: :desc) }

  def self.extract(text)
    text.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.map(&:downcase).uniq
  end
end
