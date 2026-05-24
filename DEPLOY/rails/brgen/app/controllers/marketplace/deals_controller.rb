# frozen_string_literal: true

module Marketplace
  class DealsController < Marketplace::BaseController
    allow_unauthenticated_access only: %i[index show]

    def index
      @deals = Marketplace::Deal.active.includes(:listing).limit(100)
      @featured_deals = @deals.select(&:featured?).first(12)
    end

    def show
      @deal = Marketplace::Deal.find(params[:id])
      @listing = @deal.listing
    end
  end
end
