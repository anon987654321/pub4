# frozen_string_literal: true

class RecipeIngredient < ApplicationRecord
  belongs_to :recipe, inverse_of: :recipe_ingredients

  validates :name, presence: true
end