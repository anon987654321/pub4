# frozen_string_literal: true

class Verse < ApplicationRecord
  include PgSearch::Model

  belongs_to :chapter
  belongs_to :book

  has_many :highlights,        dependent: :destroy
  has_many :bookmarks,         dependent: :destroy
  has_many :word_studies,      dependent: :destroy
  has_many :cross_references,  dependent: :destroy
  has_many :target_verses,     through: :cross_references

  validates :number, :content, presence: true
  validates :number, uniqueness: { scope: :chapter_id }

  pg_search_scope :full_text_search,
    against: :content,
    using: { tsearch: { prefix: true, dictionary: "english" } }

  scope :in_chapter, ->(chapter) { where(chapter: chapter).order(:number) }

  def reference
    "#{book.name} #{chapter.number}:#{number}"
  end
end
