# frozen_string_literal: true

class Verse < ApplicationRecord
  belongs_to :chapter
  belongs_to :book

  has_many :highlights,       dependent: :destroy
  has_many :bookmarks,        dependent: :destroy
  has_many :word_studies,     dependent: :destroy
  has_many :cross_references, dependent: :destroy
  has_many :target_verses,    through: :cross_references

  validates :number, :content, presence: true
  validates :number, uniqueness: { scope: :chapter_id }

  scope :in_chapter, ->(chapter) { where(chapter: chapter).order(:number) }
  scope :full_text_search, ->(q) {
    ids = connection.select_values(sanitize_sql_array(["SELECT rowid FROM verses_fts WHERE verses_fts MATCH ?", q]))
    ids.any? ? where(id: ids) : none
  }

  def reference
    "#{book.name} #{chapter.number}:#{number}"
  end
end
