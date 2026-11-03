# frozen_string_literal: true

class Kitchen < ApplicationRecord
  has_many :menu_categories, dependent: :destroy
  has_many :menu_items, through: :menu_categories
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  # The hours in the reader's language; Norwegian is the kitchen's own wording
  # and the fallback when no English one is set.
  def localized_opening_hours
    (I18n.locale == :en && opening_hours_en.presence) || opening_hours
  end
end
