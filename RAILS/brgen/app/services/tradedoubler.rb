# frozen_string_literal: true

require "net/http"
require "json"

# TradeDoubler product feed client.
#
# STATUS: brgen.no is not yet an approved TradeDoubler publisher. Everything
# here is gated on TRADEDOUBLER_TOKEN and returns empty without it, so the
# deals sidebar degrades to nothing rather than erroring. Approval is a manual,
# two-step process that cannot be automated from here:
#
#   1. Apply as a publisher and get the site itself approved.
#   2. Apply to each advertiser programme separately — each approves you on its
#      own terms, and only approved programmes appear in your feed.
#
# Once that is done, set TRADEDOUBLER_TOKEN (and TRADEDOUBLER_MARKET, default
# NO) and run `rake affiliate:import` to populate AffiliateProduct.
#
# UNVERIFIED: the response shape below has not been checked against a live
# response, because that needs a token. `parse` therefore accepts both the
# nested XML-ish shape ({"products" => {"product" => [...]}}) and the flat JSON
# shape ({"products" => [...]}) rather than betting on one — the previous
# version only handled the former, which would have returned zero products on
# the first real call if the API answers with the latter.
module Tradedoubler
  BASE = "https://api.tradedoubler.com/1.0"
  # TradeDoubler caps page size; keep requests modest and paginate instead.
  PAGE_SIZE = 100
  MAX_PAGES = 20

  # `placeholder` travels with the deal so the view can label it. Rendering a
  # seeded placeholder as an ordinary paid deal would be dishonest to the
  # visitor and unreconcilable for us.
  Deal = Data.define(:title, :description, :price, :currency, :image_url, :click_url, :merchant, :placeholder)

  class << self
    def token = ENV["TRADEDOUBLER_TOKEN"].presence
    def market = ENV.fetch("TRADEDOUBLER_MARKET", "NO")
    def configured? = token.present?

    # Read path for views. Prefers the imported table (no outbound call inside a
    # render, survives an outage, and is what seeds populate); falls back to a
    # live call only when the table has nothing for this category.
    def deals(category: nil, limit: 8)
      stored = stored_deals(category: category, limit: limit)
      return stored if stored.any?
      return [] unless configured?

      Rails.cache.fetch(cache_key(category), expires_in: cache_ttl_for(:search_results)) do
        fetch_deals(category: category, limit: limit)
      end
    end

    def stored_deals(category: nil, limit: 8)
      return [] unless AffiliateProduct.table_exists?

      AffiliateProduct.sellable
                      .for_market(market)
                      .for_category(category)
                      .limit(limit)
                      .map { |product| to_deal(product) }
    rescue ActiveRecord::StatementInvalid
      # Pre-migration boot (deploy ordering) must not take down the page.
      []
    end

    # Write path. Walks the feed and upserts into AffiliateProduct.
    # Returns the number of rows written.
    def import!(category: nil, pages: MAX_PAGES)
      return 0 unless configured?

      written = 0
      (1..pages).each do |page|
        rows = fetch_page(category: category, page: page)
        break if rows.empty?

        rows.each do |row|
          external_id = row[:external_id]
          # Without a stable network id there is no upsert key, and re-imports
          # would duplicate the row on every run.
          next if external_id.blank? || row[:click_url].blank? || row[:title].blank?

          AffiliateProduct.upsert_from_feed!(
            source: "tradedoubler",
            external_id: external_id,
            title: row[:title],
            description: row[:description],
            merchant: row[:merchant],
            program_id: row[:program_id],
            price_cents: row[:price_cents],
            currency: row[:currency],
            image_url: row[:image_url],
            click_url: row[:click_url],
            category: category.presence || row[:category],
            market: market,
            in_stock: row[:in_stock],
            placeholder: false
          )
          written += 1
        end

        break if rows.size < PAGE_SIZE
      end

      written
    end

    def fetch_deals(category:, limit:)
      fetch_page(category: category, page: 1).first(limit).map do |row|
        Deal.new(
          title: row[:title].to_s,
          description: row[:description].to_s.truncate(120),
          price: row[:price_cents] ? format("%.2f", row[:price_cents] / 100.0) : "",
          currency: row[:currency].to_s,
          image_url: row[:image_url].to_s,
          click_url: row[:click_url].to_s,
          merchant: row[:merchant].to_s,
          placeholder: false
        )
      end
    end

    def fetch_page(category:, page: 1)
      params = { token: token, pageSize: PAGE_SIZE, page: page, format: "json" }
      params[:category] = category if category.present?
      uri = URI("#{BASE}/products")
      uri.query = URI.encode_www_form(params)

      res = Net::HTTP.get_response(uri)
      return [] unless res.is_a?(Net::HTTPSuccess)

      parse(JSON.parse(res.body))
    rescue JSON::ParserError, StandardError => e
      Ground::Swallow.log(e, context: "Tradedoubler.fetch_page")
      []
    end

    # Normalises a feed payload into plain hashes. Tolerant of both response
    # shapes and of fields arriving either at the top level or under "fields".
    def parse(body)
      Array(extract_products(body)).filter_map do |product|
        next unless product.is_a?(Hash)

        fields = product["fields"].is_a?(Hash) ? product["fields"] : {}
        dig = ->(*keys) { keys.filter_map { |k| product[k] || fields[k] }.first }

        {
          external_id: dig.call("productId", "id", "productID", "asin").to_s.presence,
          title: dig.call("name", "productName", "title").to_s.presence,
          description: dig.call("description", "productDescription").to_s.truncate(500),
          merchant: product.dig("program", "name").presence || dig.call("merchantName", "advertiser").to_s.presence,
          program_id: (product.dig("program", "id") || dig.call("programId")).to_s.presence,
          price_cents: to_cents(dig.call("price", "Price", "priceValue")),
          currency: dig.call("currency", "Currency").to_s.presence,
          image_url: dig.call("imageUrl", "productImage", "imageURL").to_s.presence,
          click_url: dig.call("productUrl", "clickUrl", "trackingUrl").to_s.presence,
          category: dig.call("categoryName", "category").to_s.presence,
          # Absent means "not reported", which should not hide the product.
          in_stock: ![ false, "false", "0", 0 ].include?(dig.call("inStock", "availability"))
        }
      end
    end

    # The two shapes this has to survive. The XML-derived JSON nests the list
    # under products.product; the plain JSON returns products as an array. A
    # single-item response may also collapse the array to one object.
    def extract_products(body)
      return [] unless body.is_a?(Hash)

      products = body["products"] || body["product"] || body["items"]
      products = products["product"] if products.is_a?(Hash) && products.key?("product")
      products = [ products ] if products.is_a?(Hash)
      products
    end

    # Feeds report price as a decimal string ("249.90"), sometimes with a
    # thousands separator or a currency suffix. Integer minor units downstream.
    def to_cents(value)
      return nil if value.blank?

      numeric = value.to_s.gsub(/[^0-9.,-]/, "").tr(",", ".")
      return nil if numeric.blank?

      (numeric.to_f * 100).round
    end

    def to_deal(product)
      Deal.new(
        title: product.title.to_s,
        description: product.description.to_s.truncate(120),
        price: product.price.to_s,
        currency: product.currency.to_s,
        image_url: product.image_url.to_s,
        click_url: product.click_url.to_s,
        merchant: product.merchant.to_s,
        placeholder: product.placeholder?
      )
    end

    def cache_key(category)
      [ "td_deals", market, category.to_s ].join("_")
    end

    def cache_ttl_for(key_type)
      if defined?(Shared::CachePolicy)
        Shared::CachePolicy.ttl_for(key_type)
      else
        { search_results: 15.minutes }.fetch(key_type.to_sym)
      end
    end
  end
end
