# frozen_string_literal: true

class Outfit < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items
  has_one_attached :image

  validates :name, presence: true
  accepts_nested_attributes_for :outfit_items, allow_destroy: true, reject_if: :reject_blank_outfit_item

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

  def reject_blank_outfit_item(attrs)
    attrs["item_id"].blank? && attrs["_destroy"].blank?
  end
end
