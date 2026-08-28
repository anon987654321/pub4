# frozen_string_literal: true

module Marketplace
  class StoresController < Marketplace::BaseController
    include Shared::LiveSearchable

    allow_unauthenticated_access only: %i[index show]

    before_action :set_store, only: %i[show edit update destroy]
    before_action :require_real_user, only: %i[new create edit update destroy]
    before_action :authorize_owner, only: %i[edit update destroy]
    before_action :load_city_places, only: %i[new create edit update]

    def index
      scope = Marketplace::Store.active.by_vertical(params[:vertical]).recent
      scope = apply_live_search(scope, columns: %w[name description vertical], vertical: "marketplace") if live_search_query.present?
      @pagy, @stores = pagy(scope)
      finish_live_search(partial: "marketplace/stores/live_search_results")
    end

    def show
      @listings = @store.listings.live.recent.limit(100)
      @other_stores = Marketplace::Store.active.where.not(id: @store.id).limit(6)
      @payouts = @store.payouts.order(created_at: :desc).limit(20) if Current.user&.id == @store.owner_id
    end

    def new
      @store = Marketplace::Store.new
    end

    def create
      @store = Marketplace::Store.new(store_params)
      @store.owner = Current.user

      if @store.save
        redirect_to shop_path(@store.slug), notice: t("marketplace.store_created", default: "Store created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @store.update(store_params)
        redirect_to shop_path(@store.slug), notice: t("marketplace.store_updated", default: "Store updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @store.destroy
      redirect_to shops_path, notice: t("marketplace.store_deleted", default: "Store removed")
    end

    private

    def set_store
      @store = Marketplace::Store.find_by!(slug: params[:id])
    end

    # owner_id, not owner: set_store finds by slug with nothing preloaded, and
    # strict_loading_by_default raises on the association read before the
    # comparison — so store edit and update failed for the owner too.
    def authorize_owner
      return if Current.user && @store.owner_id == Current.user.id

      redirect_to shop_path(@store.slug), alert: t("marketplace.store_not_allowed", default: "Not allowed")
    end

    def store_params
      params.require(:store).permit(:name, :slug, :description, :vertical, :place_id, :stripe_connect_id)
    end

    def load_city_places
      city = Current.city_record
      @places = city ? Place.where(city_id: city.id).order(:name) : Place.none
    end
  end
end
