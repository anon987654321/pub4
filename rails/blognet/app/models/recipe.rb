# frozen_string_literal: true

class Recipe < ApplicationRecord
  self.table_name = "blognet_recipes"
  has_many :ingredients, dependent: :destroy

  def scale_ingredients(factor)
    ingredients.map do |ing|
      { name: ing.name, scaled_quantity: (ing.base_quantity * factor).round(2), unit: ing.unit }
    end
  end
end
