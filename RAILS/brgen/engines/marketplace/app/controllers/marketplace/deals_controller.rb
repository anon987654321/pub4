# frozen_string_literal: true

module Marketplace
  class DealsController < Marketplace::BaseController
    include Shared::LiveSearchable

    allow_unauthenticated_access only: %i[index show]

    def index
      scope = Marketplace::Deal.live.includes(listing: { photos_attachments: :blob })
      scope = scope.matching(live_search_query) if live_search_query.present?
      @featured_deals = scope.featured.limit(12).to_a if live_search_query.blank?
      @pagy, @deals = pagy(scope)
      finish_live_search(partial: "marketplace/deals/live_search_results")
    end

    def show
      @deal = Marketplace::Deal.live.find(params[:id])
      @listing = @deal.listing
    end
  end
end
