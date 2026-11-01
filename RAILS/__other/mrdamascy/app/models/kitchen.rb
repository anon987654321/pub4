# frozen_string_literal: true

class Kitchen < ApplicationRecord
  has_many :menu_categories, dependent: :destroy
  has_many :menu_items, through: :menu_categories
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
