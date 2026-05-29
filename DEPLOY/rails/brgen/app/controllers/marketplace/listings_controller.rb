# frozen_string_literal: true

class Marketplace::ListingsController < Marketplace::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy]

  def index
    scope = Marketplace::Listing.active.includes(:user, :category)
    scope = scope.where("title LIKE ?", "%#{params[:q]}%") if params[:q].present?
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    @pagy, @listings = pagy(scope.recent)
    @categories = Marketplace::Category.roots.includes(:children)

    # Schema.org ItemList for the marketplace listings page
    if @listings.any?
      content_for :json_ld, item_list_schema(@listings, title: "Markedsplass")
    end
  end

  def show
    @listing.increment!(:views_count)
    @order = Marketplace::Order.new if authenticated?

    # Schema.org Product markup for SEO (uses shared SchemaHelper)
    content_for :json_ld, json_ld_for(@listing, type: :product)
  end

  def new
    @listing   = Marketplace::Listing.new
    @categories = Marketplace::Category.all
  end

  def create
    @listing = Current.user.marketplace_listings.build(listing_params)
    if @listing.save
      preset = params[:marketplace_listing][:preset].presence
      PostproJob.perform_later(@listing.to_gid.to_s, preset, "photos") if preset && @listing.photos.attached?
      record_listing_activity!
      redirect_to marketplace_listing_path(@listing), notice: "Listed"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = Marketplace::Category.all
  end

  def update
    @listing.update(listing_params) ?
      redirect_to(marketplace_listing_path(@listing)) :
      render(:edit, status: :unprocessable_entity)
  end

  def destroy
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

  def record_listing_activity!
    return unless defined?(ActivityEventRecorder)

    ActivityEventRecorder.call(
      actor: Current.user,
      event_name: "ListingCreated",
      object: @listing,
      source_vertical: "marketplace",
      locality: @listing.location
    )
  end
end
