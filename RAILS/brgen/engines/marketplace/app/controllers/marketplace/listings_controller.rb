# frozen_string_literal: true

class Marketplace::ListingsController < Marketplace::BaseController
  include Shared::FindableBySlug
  include Shared::LiveSearchable
  include Shared::TwoFactorAuth

  rate_limit to: 20, within: 3.minutes, only: %i[create],
    with: -> { redirect_to listings_path, alert: t("flash.listings_rate_limited") }

  allow_unauthenticated_access only: %i[index show]
  before_action :require_user_session, only: %i[new create]
  before_action :set_listing, only: %i[show edit update destroy renew]
  # 2FA only for real accounts; guests list without identity ceremony.
  before_action -> { require_two_factor!(Current.user) }, only: %i[new create], if: :authenticated?

  def index
    scope = policy_scope(Marketplace::Listing).with_attached_photos.includes(:user, :category)
    scope = apply_live_search(scope, columns: %w[title description location], vertical: "marketplace", filters: { category_id: params[:category_id] }.compact) if live_search_query.present?
    # Counted before the facet filters narrow it: a facet's own number has to be
    # "how many if you pick this", not "how many of what you already picked".
    @facets = Marketplace::ListingFacets.new(scope, params)
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    scope = scope.where(condition: params[:condition]) if params[:condition].present?
    scope = scope.casual if params[:from] == "person"
    scope = scope.from_shops if params[:from] == "shop"
    @search_lat = params[:lat].presence
    @search_lng = params[:lng].presence
    @radius_km = Marketplace::Listing.radius_from(params[:radius_km].presence || Marketplace::Listing::DEFAULT_RADIUS_KM)
    if @search_lat.present? && @search_lng.present?
      scope = scope.near(@search_lat, @search_lng, @radius_km)
    end
    # Price + sort facets (Amazon/Craigslist-style browsing, was recency only).
    scope = scope.where("price_cents >= ?", (params[:min_price].to_f * 100).to_i) if params[:min_price].present?
    scope = scope.where("price_cents <= ?", (params[:max_price].to_f * 100).to_i) if params[:max_price].present?
    @sort = %w[recent price_low price_high].include?(params[:sort]) ? params[:sort] : "recent"
    sorted = case @sort
             when "price_low"  then scope.order(price_cents: :asc)
             when "price_high" then scope.order(price_cents: :desc)
             else scope.recent
             end
    @pagy, @listings = pagy(sorted)
    @listing_distances = listing_distances(@listings, @search_lat, @search_lng)
    @categories = Marketplace::Category.roots.includes(:children)
    @top_offers = top_offers_for_index
    @favorited_listing_ids = favorited_listing_ids_for(@listings, @top_offers)

    finish_live_search(partial: "marketplace/listings/live_search_results")
  end

  def show
    authorize @listing
    @listing.increment!(:views_count)
    @order = Marketplace::Order.new if Current.user.present?
    @reviews = @listing.reviews.includes(:user).order(created_at: :desc)
    @review = Marketplace::Review.new if Current.user.present? && @listing.reviewable_by?(Current.user)
    @nearby_listings = nearby_listings_for(@listing)
    @questions = @listing.questions.includes(:user, :answered_by).for_display
    @variants = @listing.variants.ordered.includes(:options).select(&:in_stock?)
    @question = Marketplace::Question.new if Current.user.present?
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
      preset = params[:listing][:preset].presence
      PostproJob.perform_later(@listing.to_gid.to_s, preset, "photos") if preset && @listing.photos.attached?
      Shared::DomainEvent.record!(
        actor: Current.user, action: "listing.created", subject: @listing,
        source_vertical: "marketplace", locality: @listing.location
      )
      redirect_to listing_path(@listing), notice: t("flash.marketplace.listing_published")
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
      redirect_to listing_path(@listing)
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    authorize @listing
    @listing.update!(status: "removed")
    redirect_to listings_path
  end

  def renew
    authorize @listing
    @listing.renew!
    redirect_to listing_path(@listing), notice: t("flash.marketplace.listing_renewed")
  end

  private

  def set_listing = (@listing = find_by_slug_or_id(Marketplace::Listing.includes(:user, :category, photos_attachments: :blob), params[:id]))

  def listing_params
    params.require(:listing).permit(
      :title, :description, :price_cents, :condition, :status, :location,
      :latitude, :longitude, :category_id, :preset, photos: []
    )
  end

  def nearby_listings_for(listing)
    return Marketplace::Listing.none unless listing.geo?

    policy_scope(Marketplace::Listing).active
      .where.not(id: listing.id)
      .nearby(listing.latitude, listing.longitude, 5)
      .limit(6)
  end

  def listing_distances(listings, lat, lng)
    return {} if lat.blank? || lng.blank?

    listings.each_with_object({}) do |listing, distances|
      distance = listing.distance_to(lat, lng)
      distances[listing.id] = distance if distance
    end
  end

  # Featured deals first; fill with popular active listings. Hidden while
  # searching or category-filtering so the grid stays the primary answer.
  def top_offers_for_index
    return [] if live_search_query.present? || params[:category_id].present?

    limit = 6
    deals = Marketplace::Deal.live.featured
      .includes(listing: { photos_attachments: :blob })
      .limit(limit)
      .to_a
    return deals if deals.size >= limit

    seen = deals.filter_map { |deal| deal.listing_id }
    fillers = policy_scope(Marketplace::Listing).active
      .with_attached_photos
      .includes(:category)
      .where.not(id: seen)
      .popular
      .limit(limit - deals.size)
      .to_a
    deals + fillers
  end

  def favorited_listing_ids_for(*collections)
    return Set.new unless Current.user.present?

    ids = collections.flatten.compact.filter_map do |row|
      row.is_a?(Marketplace::Deal) ? row.listing_id : row.id
    end
    return Set.new if ids.empty?

    Current.user.marketplace_favorites.where(listing_id: ids).pluck(:listing_id).to_set
  end
end
