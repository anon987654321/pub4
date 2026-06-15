# frozen_string_literal: true

module Marketplace
  class StoresController < Marketplace::BaseController
    allow_unauthenticated_access only: %i[index show]

    def index
      @stores = Marketplace::Store.active.by_vertical(params[:vertical]).recent.limit(100)
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
      params.expect(:store => [:name, :slug, :description, :vertical])
    end
  end
end
