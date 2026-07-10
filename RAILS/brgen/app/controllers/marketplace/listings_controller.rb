# frozen_string_literal: true

class Marketplace::ListingsController < Marketplace::BaseController
  include Shared::LiveSearchable
  include Shared::TwoFactorAuth

  rate_limit to: 20, within: 3.minutes, only: %i[create],
    with: -> { redirect_to marketplace_listings_path, alert: "Try again later." }

  allow_unauthenticated_access only: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy]
  before_action -> { require_two_factor!(Current.user) }, only: %i[new create], if: :authenticated?

  def index
    scope = policy_scope(Marketplace::Listing).includes(:user, :category)
    scope = apply_live_search(scope, columns: %w[title description location], vertical: "marketplace", filters: { category_id: params[:category_id] }.compact) if live_search_query.present?
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    @search_lat = params[:lat].presence
    @search_lng = params[:lng].presence
    @radius_km = Marketplace::Listing.radius_from(params[:radius_km].presence || Marketplace::Listing::DEFAULT_RADIUS_KM)
    if @search_lat.present? && @search_lng.present?
      scope = scope.near(@search_lat, @search_lng, @radius_km)
    end
    @pagy, @listings = pagy(scope.recent)
    @listing_distances = listing_distances(@listings, @search_lat, @search_lng)
    @categories = Marketplace::Category.roots.includes(:children)

    finish_live_search(partial: "marketplace/listings/live_search_results")
  end

  def show
    authorize @listing
    @listing.increment!(:views_count)
    @order = Marketplace::Order.new if authenticated?
    @reviews = @listing.reviews.includes(:user).order(created_at: :desc)
    @review = Marketplace::Review.new if authenticated? && @listing.reviewable_by?(Current.user)
  end

  def new
    authorize Marketplace::Listing
    @listing   = Marketplace::Listing.new
    @categories = Marketplace::Category.all
  end

  def create
    authorize Marketplace::Listing
    @listing = Current.user.marketplace_listings.build(listing_params)
    if @listing.save
      preset = params[:marketplace_listing][:preset].presence
      PostproJob.perform_later(@listing.to_gid.to_s, preset, "photos") if preset && @listing.photos.attached?
      Shared::DomainEvent.record!(
        actor: Current.user, action: "listing.created", subject: @listing,
        source_vertical: "marketplace", locality: @listing.location
      )
      redirect_to marketplace_listing_path(@listing), notice: "Listed"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @listing
    @categories = Marketplace::Category.all
  end

  def update
    authorize @listing
    if @listing.update(listing_params)
      Shared::DomainEvent.record!(
        actor: Current.user, action: "listing.updated", subject: @listing,
        source_vertical: "marketplace", locality: @listing.location
      )
      redirect_to marketplace_listing_path(@listing)
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    authorize @listing
    @listing.update!(status: "removed")
    redirect_to marketplace_listings_path
  end

  private

  def set_listing = (@listing = Marketplace::Listing.includes(:user, :category, photos_attachments: :blob).find(params[:id]))

  def listing_params
    params.require(:marketplace_listing).permit(
      :title, :description, :price_cents, :condition, :status, :location,
      :latitude, :longitude, :category_id, :preset, photos: []
    )
  end

  def listing_distances(listings, lat, lng)
    return {} if lat.blank? || lng.blank?

    listings.each_with_object({}) do |listing, distances|
      distance = listing.distance_to(lat, lng)
      distances[listing.id] = distance if distance
    end
  end
end
