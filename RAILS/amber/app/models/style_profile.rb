# frozen_string_literal: true

class StyleProfile < ApplicationRecord
  belongs_to :user

  validates :body_type, length: { maximum: 128 }, allow_blank: true
  validates :style_preferences, length: { maximum: 2_000 }, allow_blank: true
  validates :preferred_colors, length: { maximum: 1_000 }, allow_blank: true
  validates :favorite_brands, length: { maximum: 1_000 }, allow_blank: true

  def color_list
    preferred_colors.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  def brand_list
    favorite_brands.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end
end
