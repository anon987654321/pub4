# frozen_string_literal: true

module Partner
  # Public redirect: /p/:token → listing/store, recording a click for attribution.
  class ClicksController < ApplicationController
    allow_unauthenticated_access only: :show

    def show
      membership = Partner::Membership.find_by!(token: params[:token])
      listing = Marketplace::Listing.find_by(id: params[:listing_id]) if params[:listing_id].present?

      digest = Partner::Click.digest_for(request.remote_ip, request.user_agent)
      Partner::Click.record!(
        membership: membership,
        visitor_digest: digest,
        listing: listing,
        user: Current.user
      )

      target = if listing
                 marketplace_listing_url_for(listing)
               else
                 marketplace_store_url_for(membership.program.store)
               end
      redirect_to target, allow_other_host: true
    end

    private

    def marketplace_listing_url_for(listing)
      if respond_to?(:marketplace_listing_path)
        marketplace_listing_path(listing)
      else
        "/listings/#{listing.id}"
      end
    rescue StandardError
      "/listings/#{listing.id}"
    end

    def marketplace_store_url_for(store)
      if respond_to?(:marketplace_shop_path)
        marketplace_shop_path(store.slug)
      else
        "/shops/#{store.slug}"
      end
    rescue StandardError
      "/shops/#{store.slug}"
    end
  end
end
