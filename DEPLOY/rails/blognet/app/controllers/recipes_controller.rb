# frozen_string_literal: true

class RecipesController < ApplicationController
  before_action :require_authentication
  before_action :set_recipe, only: %i[show edit update]

  def show
    content_for :json_ld, json_ld_for(@recipe, type: :recipe) if respond_to?(:json_ld_for, true)
  end

  def new
    @recipe = Current.user.recipes.build
    3.times { @recipe.recipe_ingredients.build }
  end

  def create
    @recipe = Current.user.recipes.build(recipe_params)
    if @recipe.save
      redirect_to @recipe, notice: "Recipe created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @recipe.update(recipe_params) ? redirect_to(@recipe, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  private

  def set_recipe
    @recipe = Recipe.includes(:recipe_ingredients).find(params[:id])
  end

  def recipe_params
    params.expect(recipe: [:title, :description, :prep_time_minutes, :cook_time_minutes, :servings, :cuisine, :post_id,
      { recipe_ingredients_attributes: [%i[id name quantity unit position _destroy]] }])
  end
end