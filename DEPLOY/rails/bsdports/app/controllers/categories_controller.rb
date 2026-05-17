class CategoriesController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  def index
    @categories = Category.order(:name).includes(:ports)
  end

  def show
    @category = Category.find_by!(slug: params[:id])
    @pagy, @ports = pagy(@category.ports.order(:name))
  end
end
