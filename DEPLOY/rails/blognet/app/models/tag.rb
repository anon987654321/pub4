# frozen_string_literal: true

class Tag < ApplicationRecord
  has_many :taggings, dependent: :destroy
  has_many :posts, through: :taggings

  validates :name, presence: true, uniqueness: true

  before_validation -> { self.name = name.to_s.strip.downcase }, on: :create

  scope :popular, -> { where("posts_count > 0").order(posts_count: :desc) }
  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM tags_fts WHERE tags_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }
  scope :autocomplete, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    search(term).or(where("name LIKE ?", "#{sanitize_sql_like(term.downcase)}%")).distinct.limit(10)
  }
end
