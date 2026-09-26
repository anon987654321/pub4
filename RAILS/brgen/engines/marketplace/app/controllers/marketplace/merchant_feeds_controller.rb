# frozen_string_literal: true

require "builder"

module Marketplace
  # Google Merchant Center product feed for first-party marketplace inventory.
  #
  # Affiliate inventory is intentionally excluded: this feed describes products
  # the marketplace itself can sell, with landing pages on the verified storefront.
  class MerchantFeedsController < Marketplace::BaseController
    allow_unauthenticated_access

    def show
      listings = Marketplace::Listing.live
        .where(kind: "goods")
        .where.not(price_cents: nil)
        .with_attached_photos
        .includes(:category, :variants)
        .recent
        .limit(10_000)
        .to_a
        .select { |listing| listing.photos.attached? }

      render xml: feed_xml(listings), content_type: "application/xml"
    end

    private

    def feed_xml(listings)
      xml = Builder::XmlMarkup.new
      xml.instruct!
      xml.rss(version: "2.0", "xmlns:g" => "http://base.google.com/ns/1.0") do
        xml.channel do
          xml.title("Brgen Marketplace")
          xml.link(storefront_url)
          xml.description("Goods listed for sale on the Brgen marketplace.")
          listings.each { |listing| product(xml, listing) }
        end
      end
      xml.target!
    end

    def product(xml, listing)
      xml.item do
        xml["g"].id(listing.id)
        xml["g"].title(feed_title(listing))
        xml["g"].description(feed_description(listing))
        xml["g"].link(listing_url(listing))
        if (photo = listing.photos.first)
          xml["g"].image_link(rails_blob_url(photo, host: request.host, protocol: request.protocol))
        end
        xml["g"].availability(listing.buyable? ? "in_stock" : "out_of_stock")
        xml["g"].price("#{format("%.2f", listing.price_cents.to_i / 100.0)} #{listing.currency.presence || "NOK"}")
        xml["g"].condition(condition_for(listing))
        xml["g"].product_type(listing.category&.name.to_s) if listing.category&.name.present?
        if listing.variants.loaded? && listing.variants.any?
          xml["g"].item_group_id("listing-#{listing.id}")
        end
      end
    end

    def feed_title(listing)
      listing.title.to_s.strip.gsub(/\s+/, " ")[0, 70]
    end

    def feed_description(listing)
      text = ActionController::Base.helpers.strip_tags(listing.description.to_s).squish
      text = "Goods listed on Brgen Marketplace." if text.blank?
      text[0, 5_000]
    end

    def condition_for(listing)
      listing.condition.to_s == "new" ? "new" : "used"
    end

    def storefront_url
      "#{request.protocol}#{request.host}"
    end

    def listing_url(listing)
      url_for(controller: "marketplace/listings", action: "show", id: listing.to_param, only_path: false)
    end
  end
end
