# frozen_string_literal: true

class FoodListingsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]
  before_action :require_real_user, except: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    scope = FoodListing.available.order(created_at: :desc)
    scope = apply_live_search(scope, columns: %w[title description city dietary_info], vertical: "food_listings") if live_search_query.present?
    if params[:lat].present? && params[:lng].present? && scope.respond_to?(:near)
      scope = scope.near(params[:lat], params[:lng], params[:radius_km] || 10)
    end
    @pagy, @listings = pagy(scope)
    finish_live_search(partial: "food_listings/live_search_results")
  end

  def show
    @request = FoodRequest.new
    @requests = @listing.food_requests.includes(:user).order(created_at: :desc) if authenticated? && @listing.user == Current.user
    @listing.record_activity!("FoodListingViewed", source_vertical: "hjerterom")
  end

  def new
    @listing = Current.user.food_listings.build
  end

  def create
    @listing = Current.user.food_listings.build(listing_params)
    if @listing.save
      Shared::DomainEvent.record!(actor: Current.user, action: "food_listing.created", subject: @listing, source_vertical: "hjerterom")
      redirect_to(@listing, notice: "Food listing created")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit; end

  def update
    if @listing.update(listing_params)
      Shared::DomainEvent.record!(actor: Current.user, action: "food_listing.updated", subject: @listing, source_vertical: "hjerterom")
      redirect_to(@listing, notice: "Updated")
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @listing.record_activity!("FoodListingRemoved", source_vertical: "hjerterom")
    @listing.destroy
    redirect_to food_listings_path, notice: "Listing removed"
  end

  private

  def set_listing  = @listing = FoodListing.find(params[:id])
  def authorize!
    redirect_to(food_listings_path, alert: "Unauthorized") unless @listing.user == Current.user
  end

  def listing_params
    params.require(:food_listing).permit(
      :title, :description, :quantity, :unit,
      :available_from, :available_until,
      :pickup_address, :city, :dietary_info
    )
  end
end
