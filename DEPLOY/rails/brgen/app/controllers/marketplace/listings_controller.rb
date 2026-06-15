# frozen_string_literal: true

class Marketplace::ListingsController < Marketplace::BaseController
  include Shared::LiveSearchable
  include Shared::TwoFactorAuth

  allow_unauthenticated_access only: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy]
  before_action -> { require_two_factor!(Current.user) }, only: %i[new create], if: :authenticated?

  def index
    scope = policy_scope(Marketplace::Listing).includes(:user, :category)
    scope = apply_live_search(scope, columns: %w[title description location], vertical: "marketplace", filters: { category_id: params[:category_id] }.compact) if live_search_query.present?
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    if params[:lat].present? && params[:lng].present?
      scope = scope.near(params[:lat], params[:lng], params[:radius_km] || 5)
    end
    @pagy, @listings = pagy(scope.recent)
    @categories = Marketplace::Category.roots.includes(:children)

    # Schema.org ItemList for the marketplace listings page
    if @listings.any?
      content_for :json_ld, item_list_schema(@listings, title: "Markedsplass")
    end

    finish_live_search(partial: "marketplace/listings/live_search_results")
  end

  def show
    authorize @listing
    @listing.increment!(:views_count)
    @order = Marketplace::Order.new if authenticated?

    # Schema.org Product markup for SEO (uses shared SchemaHelper)
    content_for :json_ld, json_ld_for(@listing, type: :product)
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
    @listing.update(listing_params) ?
      redirect_to(marketplace_listing_path(@listing)) :
      render(:edit, status: :unprocessable_entity)
  end

  def destroy
    authorize @listing
    @listing.update!(status: "removed")
    redirect_to marketplace_listings_path
  end

  private

  def set_listing = (@listing = Marketplace::Listing.find(params[:id]))

  def listing_params
    params.require(:marketplace_listing).permit(
      :title, :description, :price_cents, :condition, :status, :location,
      :category_id, :preset, photos: []
    )
  end
end
