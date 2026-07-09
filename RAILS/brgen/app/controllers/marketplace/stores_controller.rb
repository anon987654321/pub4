# frozen_string_literal: true

module Marketplace
  class StoresController < Marketplace::BaseController
    include Shared::LiveSearchable

    allow_unauthenticated_access only: %i[index show]

    def index
      scope = Marketplace::Store.active.by_vertical(params[:vertical]).recent
      scope = apply_live_search(scope, columns: %w[name description vertical], vertical: "marketplace") if live_search_query.present?
      @stores = scope.limit(100)
      finish_live_search(partial: "marketplace/stores/live_search_results")
    end

    def show
      @store = Marketplace::Store.find_by!(slug: params[:id])
      @listings = @store.listings.active.recent.limit(100)
    end

    def new
      @store = Marketplace::Store.new
    end

    def create
      @store = Marketplace::Store.new(store_params)
      @store.owner = Current.user

      if @store.save
        redirect_to marketplace_shop_path(@store.slug), notice: t("marketplace.store_created", default: "Store created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def store_params
      params.require(:store).permit(:name, :slug, :description, :vertical)
    end
  end
end
