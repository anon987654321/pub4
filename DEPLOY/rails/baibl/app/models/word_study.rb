# frozen_string_literal: true

class WordStudy < ApplicationRecord
  belongs_to :verse

  LANGUAGES = %w[hebrew greek arabic].freeze
  validates :position, :word, presence: true
  validates :position, uniqueness: { scope: :verse_id }
  validates :language, inclusion: { in: LANGUAGES }, allow_nil: true

  def strongs_url
    return nil unless strongs.present?
    prefix = strongs.start_with?("H") ? "hebrew" : "greek"
    "https://www.blueletterbible.org/lexicon/#{strongs.downcase}/#{prefix}/wlc/0-1/"
  end
end
