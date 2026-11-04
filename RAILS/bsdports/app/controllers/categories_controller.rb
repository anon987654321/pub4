# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]

  def index
    scope = Category.order(:name)
    scope = apply_live_search(scope, columns: %w[name description], vertical: "categories") if live_search_query.present?
    @pagy, @categories = pagy(scope)
    # One grouped COUNT for the page; includes(:ports) loaded every port row
    # of every category on it to print a number.
    @port_counts = Port.where(category_id: @categories.map(&:id)).group(:category_id).count
    finish_live_search(partial: "categories/live_search_results")
  end

  def show
    @category = Category.find_by!(slug: params[:id])
    @pagy, @ports = pagy(@category.ports.order(:name))
    @category.record_activity!("CategoryViewed", source_vertical: "bsdports") unless passive_request?
  end
end
