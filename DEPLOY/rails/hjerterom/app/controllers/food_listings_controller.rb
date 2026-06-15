# frozen_string_literal: true

class FoodListingsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    scope = FoodListing.available.order(created_at: :desc)
    scope = apply_live_search(scope, columns: %w[title description city dietary_info], vertical: "food_listings") if live_search_query.present?
    if params[:lat].present? && params[:lng].present? && scope.respond_to?(:near)
      scope = scope.near(params[:lat], params[:lng], params[:radius_km] || 10)
    end
    @pagy, @listings = pagy(scope)
  end

  def show
    @request = FoodRequest.new
  end

  def new
    @listing = Current.user.food_listings.build
  end

  def create
    @listing = Current.user.food_listings.build(listing_params)
    @listing.save ? redirect_to(@listing, notice: "Food listing created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @listing.update(listing_params) ? redirect_to(@listing, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @listing.destroy
    redirect_to food_listings_path, notice: "Listing removed"
  end

  private

  def set_listing  = @listing = FoodListing.find(params[:id])
  def authorize!   = redirect_to(food_listings_path, alert: "Unauthorized") unless @listing.user == Current.user

  def listing_params
    params.require(:food_listing).permit(
      :title, :description, :quantity, :unit,
      :available_from, :available_until,
      :pickup_address, :city, :dietary_info
    )
  end
end
