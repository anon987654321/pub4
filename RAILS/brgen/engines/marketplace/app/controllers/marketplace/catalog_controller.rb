# frozen_string_literal: true

require "uri"

module Marketplace
  class CatalogController < Marketplace::BaseController
    include StorefrontSearch

    allow_unauthenticated_access only: :index

    def index
      scope = Marketplace::Listing.publicly_visible
                                   .includes(:user, :category, :store)
                                   .with_attached_photos

      @kind = Marketplace::Listing.kind_from(params[:kind])
      scope = scope.where(kind: @kind)
      scope = scope.casual if params[:from] == "person"
      scope = scope.from_shops if params[:from] == "shop"
      scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
      scope = scope.where("price_cents >= ?", (params[:min_price].to_f * 100).to_i) if params[:min_price].present?
      scope = scope.where("price_cents <= ?", (params[:max_price].to_f * 100).to_i) if params[:max_price].present?

      query = params[:q].to_s.strip
      scope = Shared::LiveSearch.call(
        scope,
        query:,
        columns: %w[title description location],
      ) if query.present?

      ranker = Marketplace::SearchRanker.new(scope, query:, viewer: Current.user)
      limit = params[:limit].to_i.clamp(1, 50)
      listings = ranker.relation.limit(limit).to_a

      render json: {
        schema: Shared::Commerce::PROTOCOL,
        generated_at: Time.current.iso8601,
        city: city_payload,
        query: query.presence,
        count: listings.length,
        items: listings.map { |listing| catalog_item(listing, ranker) }
      }
    end

    private

    def city_payload
      city = Current.city_record
      {
        id: city&.id,
        name: city&.name,
        currency: Current.currency.presence || "NOK"
      }
    end

    def catalog_item(listing, ranker)
      {
        id: Shared::Commerce.canonical_id(
          source: "brgen",
          type: "listing",
          city_id: listing.city_id,
          record_id: listing.id
        ),
        type: "marketplace_listing",
        title: listing.title,
        description: listing.description.to_s.tr("\n", " ")[0, 500],
        category: {
          id: listing.category_id,
          name: listing.category&.name
        },
        price: {
          cents: listing.price_cents,
          currency: listing.currency.presence || "NOK"
        },
        condition: listing.condition_label,
        availability: {
          status: listing.status,
          quantity: listing.available_quantity,
          buyable: listing.buyable?
        },
        delivery: {
          code: Marketplace::Listing::DELIVERY_PROMISES.key(listing.delivery_promise),
          label: listing.delivery_badge,
          fulfilment: Marketplace::Listing::FULFILMENT_METHODS.key(listing.fulfilment_method)
        },
        seller: {
          kind: listing.store_id.present? ? "shop" : "person",
          name: listing.store&.name || listing.user&.display_name
        },
        trust: {
          seller_score: listing.seller_score.to_f,
          rating: listing.rating.to_f,
          reviews: listing.reviews_count.to_i,
          ranking_score: listing.ranking_score.to_f
        },
        url: listing_url(listing),
        image_url: catalog_image_url(listing),
        reasons: ranker.reasons(listing),
        handoff: {
          amber_url: amber_handoff_url(listing)
        },
        metadata: {
          locality: listing.location,
          source: "brgen",
          protocol: Shared::Commerce::PROTOCOL
        }
      }
    end

    def catalog_image_url(listing)
      return unless listing.photos.attached?

      url_for(listing.photos.first)
    end

    def amber_handoff_url(listing)
      Shared::Commerce.amber_handoff_url(
        base: ENV.fetch("AMBER_PUBLIC_URL", "https://amberapp.art"),
        title: listing.title,
        category: amber_category(listing.category&.name),
        source_url: listing_url(listing),
        commerce_key: Shared::Commerce.canonical_id(
          source: "brgen",
          type: "listing",
          city_id: listing.city_id,
          record_id: listing.id
        )
      )
    end

    def amber_category(name)
      Item::CATEGORIES.find { |category| category.casecmp?(name.to_s) } if defined?(Item)
    end
  end
end
