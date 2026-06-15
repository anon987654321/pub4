# frozen_string_literal: true

class Outfit < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items
  has_one_attached :image

  validates :name, presence: true

  broadcasts_refreshes

  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM outfits_fts WHERE outfits_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }

  def like!
    increment!(:likes_count)
  end

  def context_label
    [season, category, occasion].compact_blank.join(" · ")
  end

  def total_wears
    items.sum { |item| item.times_worn.to_i }
  end

  def estimated_value
    items.sum { |item| item.price.to_f }
  end
end
