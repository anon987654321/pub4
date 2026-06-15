# frozen_string_literal: true

class Recipe < ApplicationRecord
  belongs_to :post, optional: true
  belongs_to :user
  has_many :recipe_ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :recipe

  accepts_nested_attributes_for :recipe_ingredients, allow_destroy: true

  validates :title, presence: true

  def total_time_minutes
    prep_time_minutes.to_i + cook_time_minutes.to_i
  end
end