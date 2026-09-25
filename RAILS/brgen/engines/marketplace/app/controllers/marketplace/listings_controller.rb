# frozen_string_literal: true

class Marketplace::ListingsController < Marketplace::BaseController
  include Shared::FindableBySlug
  include StorefrontSearch
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
    @kind = Marketplace::Listing.kind_from(params[:kind])
    scope = scope.where(kind: @kind)
    scope = scope.casual if params[:from] == "person"
    scope = scope.from_shops if params[:from] == "shop"
    # Counted after kind and source, which the grid always applies, and before
    # the facet filters narrow it: a facet's own number has to be "how many if
    # you pick this", not "how many of what you already picked".
    @facets = Marketplace::ListingFacets.new(scope, params)
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    scope = scope.where(condition: params[:condition]) if params[:condition].present?
    @search_lat = params[:lat].presence
    @search_lng = params[:lng].presence
    @radius_km = Marketplace::Listing.radius_from(params[:radius_km].presence || Marketplace::Listing::DEFAULT_RADIUS_KM)
    if @search_lat.present? && @search_lng.present?
      scope = scope.near(@search_lat, @search_lng, @radius_km)
    end
    # Price + sort facets (Amazon/Craigslist-style browsing, was recency only).
    scope = scope.where("price_cents >= ?", (params[:min_price].to_f * 100).to_i) if params[:min_price].present?
    scope = scope.where("price_cents <= ?", (params[:max_price].to_f * 100).to_i) if params[:max_price].present?
    @sort = Marketplace::Listing::SORTS.include?(params[:sort]) ? params[:sort] : "recent"
    @pagy, @listings = pagy(scope.sorted_by(@sort))
    @listing_distances = listing_distances(@listings, lat: @search_lat, lng: @search_lng)
    @categories = Marketplace::Category.roots.includes(:children)
    @top_offers = top_offers_for_index(@kind)
    @favorited_listing_ids = favorited_listing_ids_for(@listings, @top_offers)
    # An empty list with nothing narrowing it means the city has none of this
    # kind yet, which the results say differently from a search that found none.
    narrowing = params.values_at(:from, :category_id, :condition, :min_price, :max_price, :lat)
    @narrowed = live_search_query.present? || narrowing.any?(&:present?)

    finish_storefront_search(partial: "marketplace/listings/live_search_results")
  end

  def show
    authorize @listing
    return if redirect_id_to_slug(@listing)

    @listing.increment!(:views_count)
    @order = Marketplace::Order.new if Current.user.present?
    @reviews = @listing.reviews.includes(:user).order(created_at: :desc)
    @review = Marketplace::Review.new if Current.user.present? && @listing.reviewable_by?(Current.user)
    @nearby_listings = nearby_listings_for(@listing)
    @questions = @listing.questions.includes(:user, :answered_by).for_display
    @variants = @listing.variants.ordered.includes(:options).in_stock
    @categories = Marketplace::Category.roots.includes(:children)
    @question = Marketplace::Question.new if Current.user.present?
  end

  def new
    authorize Marketplace::Listing
    @kind = Marketplace::Listing.kind_from(params[:kind])
    @listing = Marketplace::Listing.new(kind: @kind)
    @listing.build_job_detail if @kind == "job"
    @listing.build_housing_detail if @kind == "housing"
    @listing.build_gig_detail if @kind == "gig"
    @categories = Marketplace::Category.all
  end

  def create
    authorize Marketplace::Listing
    @listing = Current.user.marketplace_listings.build(listing_params_for_kind(listing_params[:kind].presence || "goods"))
    if @listing.save
      preset = params[:listing][:preset].presence
      if preset && @listing.photos.attached?
        @listing.mark_photo_status!("pending")
        PostproJob.perform_later(@listing.to_gid.to_s, preset, "photos")
      end
      Shared::DomainEvent.record!(
        actor: Current.user, action: "listing.created", subject: @listing,
        source_vertical: "marketplace", locality: @listing.location
      )
      redirect_to listing_path(@listing), notice: t("flash.marketplace.listing_published")
    else
      # The form reads both of these and create set neither, so a refused
      # listing answered 500 rather than showing the reader what was wrong with
      # it. Only the kinds work made that reachable — until now every refusal
      # here was a validation the form itself prevented.
      @kind = @listing.kind.presence || "goods"
      @categories = Marketplace::Category.all
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @listing
    @categories = Marketplace::Category.all
  end

  def update
    authorize @listing
    if @listing.update(listing_update_params)
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
      :latitude, :longitude, :category_id, :preset, :kind, photos: [],
      job_detail_attributes: %i[employer employment_type salary_min_cents salary_max_cents remote],
      housing_detail_attributes: %i[rent_cents deposit_cents rooms size_sqm available_from housing_type],
      gig_detail_attributes: %i[pay_cents starts_at hours]
    )
  end

  # Only the detail block for the kind being listed. Permitting all three would
  # let a job advert arrive carrying rent, and the row would sit there with
  # nothing rendering it.
  def listing_params_for_kind(kind)
    permitted = listing_params
    %w[job housing gig].each do |other_kind|
      permitted.delete("#{other_kind}_detail_attributes") unless kind == other_kind
    end
    permitted
  end

  # kind is fixed at create. Switching a goods listing to a job afterwards would
  # drop the price requirement from a listing buyers already hold offers on.
  def listing_update_params = listing_params_for_kind(@listing.kind).except(:kind)

  def nearby_listings_for(listing)
    return Marketplace::Listing.none unless listing.geo?

    # Nearby means nearby of the same kind: a flat for rent has nothing to say
    # about the bicycles around it.
    policy_scope(Marketplace::Listing).active
      .where(kind: listing.kind)
      .where.not(id: listing.id)
      .nearby(listing.latitude, listing.longitude, 5)
      .limit(6)
  end

  def listing_distances(listings, lat:, lng:)
    return {} if lat.blank? || lng.blank?

    listings.each_with_object({}) do |listing, distances|
      distance = listing.distance_to(lat, lng)
      distances[listing.id] = distance if distance
    end
  end

  # Featured deals first; fill with popular active listings. Hidden while
  # searching or category-filtering so the grid stays the primary answer.
  #
  # Same kind as the grid below it. The strip used to draw from every listing
  # there is, so the moment a kind other than goods existed, a bicycle search
  # carried a job advert above it — the filter the grid applies has to apply
  # here or the page contradicts itself.
  def top_offers_for_index(kind)
    return [] if live_search_query.present? || params[:category_id].present?

    limit = 6
    deals = Marketplace::Deal.live.featured
      .merge(Marketplace::Listing.where(kind: kind))
      .includes(listing: { photos_attachments: :blob })
      .limit(limit)
      .to_a
    return deals if deals.size >= limit

    seen = deals.filter_map(&:listing_id)
    fillers = policy_scope(Marketplace::Listing).active
      .where(kind: kind)
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
