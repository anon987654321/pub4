# frozen_string_literal: true

module Partner
  # Public redirect: /p/:token → listing/store, recording a click for attribution.
  class ClicksController < ApplicationController
    allow_unauthenticated_access only: :show

    def show
      membership = Partner::Membership.find_by!(token: params[:token])
      listing = Marketplace::Listing.find_by(id: params[:listing_id]) if params[:listing_id].present?
      if listing && membership.program.store_id && listing.store_id != membership.program.store_id
        listing = nil
      end

      digest = Partner::Click.digest_for(request.remote_ip, request.user_agent)
      Partner::Click.record!(
        membership: membership,
        visitor_digest: digest,
        listing: listing,
        user: Current.user
      )

      # Both helpers return internal relative paths (Rails *_path helpers or the
      # "/listings/:id" / "/shops/:slug" fallbacks), never another host — so the
      # target is always same-origin. allow_other_host: true was therefore unused
      # and read to Brakeman as an open redirect (params-derived value + off-host
      # opt-out). Dropping it keeps the same behaviour and lets Rails' default
      # host guard reject anything that somehow resolves off-site.
      target = if listing
                 marketplace_listing_url_for(listing)
      else
                 marketplace_store_url_for(membership.program.store)
      end
      redirect_to target
    end

    private

    def marketplace_listing_url_for(listing)
      if respond_to?(:marketplace)
        marketplace.listing_path(listing)
      else
        "/listings/#{listing.id}"
      end
    rescue StandardError
      "/listings/#{listing.id}"
    end

    def marketplace_store_url_for(store)
      if respond_to?(:marketplace)
        marketplace.shop_path(store.slug)
      else
        "/shops/#{store.slug}"
      end
    rescue StandardError
      "/shops/#{store.slug}"
    end
  end
end
