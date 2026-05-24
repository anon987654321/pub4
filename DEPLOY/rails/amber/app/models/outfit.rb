# frozen_string_literal: true

class Outfit < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items

  validates :name, presence: true

  broadcasts_refreshes

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
