# frozen_string_literal: true

module Marketplace
  class ListingsController < ApplicationController
    before_action :set_listing, only: %i[show edit update destroy]

    def index
      @listings = Listing.published.includes(:vendor, :category)
      @listings = @listings.where(category_id: params[:category_id]) if params[:category_id]

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
    end

    def create
      @listing = Listing.new(listing_params.merge(vendor: current_user.vendor))

      if @listing.save
        EventDispatcher.dispatch(:ListingCreated, @listing)
        redirect_to @listing, notice: "Listing created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_listing
      @listing = Listing.find(params[:id])
    end

    def listing_params
      params.require(:listing).permit(
        :title,
        :description,
        :price_cents,
        :category_id,
        :status,
        photos: []
      )
    end
  end
end
