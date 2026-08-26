# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "time"

# Amazon Associates product feed via the Creators API (PA-API 5.0 retired 2026-05-15).
#
# Public contract matches Tradedoubler so Affiliate::NETWORKS treats both the same:
#   configured? / deals(category:, limit:) / import!(category:, pages:)
#
# Two modes:
#
#   1. Tag-only (works now with approved marketplace tags)
#      Set AMAZON_ASSOCIATE_TAG_SE, AMAZON_ASSOCIATE_TAG_NL, AMAZON_ASSOCIATE_TAG_FR, …
#      Use seed_asins! / rake affiliate:amazon_seed to write AffiliateProduct rows
#      with correctly tagged DetailPage-style URLs. No Creators API needed.
#      This is how you generate the 10 qualifying sales that unlock the API.
#
#   2. Creators API catalog (after 10 sales / 30 days)
#      Set AMAZON_CREATORS_CLIENT_ID, AMAZON_CREATORS_CLIENT_SECRET,
#      AMAZON_CREATORS_VERSION (e.g. 3.2 for EU), plus at least one marketplace tag.
#      Then deals/import! call SearchItems / GetItems against creatorsapi.amazon.
#
# Marketplace routing and tags live in Shared::AmazonMarketplace — never use a
# single global tag across storefronts; a DE tag on a SE link pays nothing.
#
# Norway has no storefront; Shared::AmazonMarketplace routes NO → DE by default.
# With SE approved, prefer amazon.se for Nordic readers when a SE tag is set.
module Shared
  module AmazonAssociates
    API_BASE = "https://creatorsapi.amazon"
    TOKEN_ENDPOINTS = {
      "3.1" => "https://api.amazon.com/auth/o2/token",      # NA
      "3.2" => "https://api.amazon.co.uk/auth/o2/token",    # EU (SE, NL, FR, DE, …)
      "3.3" => "https://api.amazon.co.jp/auth/o2/token",    # FE
      "2.1" => "https://creatorsapi.auth.us-east-1.amazoncognito.com/oauth2/token",
      "2.2" => "https://creatorsapi.auth.eu-south-2.amazoncognito.com/oauth2/token",
      "2.3" => "https://creatorsapi.auth.ap-northeast-1.amazoncognito.com/oauth2/token",
    }.freeze
    PAGE_SIZE = 10
    MAX_PAGES = 10
    TOKEN_CACHE_KEY = "amazon_associates/creators_access_token"
    DEFAULT_RESOURCES = %w[
      images.primary.medium
      itemInfo.title
      itemInfo.byLineInfo
      offersV2.listings.price
      offersV2.listings.availability
    ].freeze

    class << self
      def client_id = ENV["AMAZON_CREATORS_CLIENT_ID"].presence || ENV["AMAZON_ACCESS_KEY"].presence
      def client_secret = ENV["AMAZON_CREATORS_CLIENT_SECRET"].presence || ENV["AMAZON_SECRET_KEY"].presence
      def version = ENV.fetch("AMAZON_CREATORS_VERSION", "3.2")
      def market = ENV.fetch("AMAZON_MARKET", "SE")

      # Catalog API ready when Creators credentials exist AND a tag for the
      # active market exists. Tag-only seeding only needs the tag.
      def configured?
        client_id.present? && client_secret.present? && partner_tag.present?
      end

      def tag_only_configured?(for_market = market)
        Shared::AmazonMarketplace.tag_for(for_market).present?
      end

      def partner_tag(for_market = market)
        Shared::AmazonMarketplace.tag_for(for_market) ||
          ENV["AMAZON_PARTNER_TAG"].presence
      end

      def marketplace_host(for_market = market)
        "www.#{Shared::AmazonMarketplace.host_for(for_market)}"
      end

      # Same contract as Tradedoubler.deals: prefer table; live only as fallback.
      def deals(category: nil, limit: 8)
        stored = stored_deals(category:, limit:)
        return stored if stored.any?
        return [] unless configured?

        Rails.cache.fetch("amazon/deals/#{market}/#{category}/#{limit}", expires_in: 15.minutes) do
          search_items(keywords: category.presence || "deals", page: 1)
            .first(limit)
            .map { |row| to_deal(row) }
        end
      rescue StandardError => e
        Rails.logger.warn("amazon_associates deals: #{e.class}: #{e.message}")
        []
      end

      def stored_deals(category: nil, limit: 8)
        return [] unless defined?(AffiliateProduct) && AffiliateProduct.table_exists?

        AffiliateProduct.sellable
                        .where(source: "amazon")
                        .for_market(market)
                        .for_category(category)
                        .limit(limit)
                        .map { |p| Affiliate.to_deal(p) }
      # The table check is on the way in, so this is a schema fault rather than an
      # absent table — and `deals` two methods up already logs exactly this way.
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("amazon_associates stored_deals: #{e.class}: #{e.message}")
        []
      end

      def import!(category: nil, pages: MAX_PAGES)
        return 0 unless configured?

        written = 0
        (1..pages).each do |page|
          rows = search_items(keywords: category.presence || "deals", page:)
          break if rows.empty?

          rows.each { |row| written += 1 if upsert_row!(row, category:) }
          break if rows.size < PAGE_SIZE
        end
        written
      rescue StandardError => e
        Rails.logger.warn("amazon_associates import: #{e.class}: #{e.message}")
        written.to_i
      end

      # Tag-only path: write AffiliateProduct rows for known ASINs with correct
      # marketplace tags. No Creators API. Use this to drive the 10 sales that
      # unlock catalog access.
      #
      # asins: array of { asin:, title:, market: "SE", category:, image_url:, price_cents:, currency: }
      # or plain ASIN strings (title becomes "Amazon product ASIN").
      def seed_asins!(asins, default_market: market)
        return 0 unless defined?(AffiliateProduct)

        written = 0
        Array(asins).each do |entry|
          row = normalize_seed_entry(entry, default_market)
          next if row[:asin].blank?
          next unless tag_only_configured?(row[:market])

          url = Shared::AmazonMarketplace.product_url(row[:asin], market: row[:market])
          next if url.blank?

          AffiliateProduct.upsert_from_feed!(
            source: "amazon",
            external_id: row[:asin],
            title: row[:title],
            description: row[:description],
            merchant: "Amazon",
            program_id: partner_tag(row[:market]),
            price_cents: row[:price_cents],
            currency: row[:currency],
            image_url: row[:image_url],
            click_url: url,
            category: row[:category],
            market: Shared::AmazonMarketplace.country_for(row[:market]),
            in_stock: true,
            placeholder: false,
          )
          written += 1
        end
        written
      end

      private

      def normalize_seed_entry(entry, default_market)
        if entry.is_a?(Hash)
          {
            asin: entry[:asin].to_s.strip.upcase.presence || entry["asin"].to_s.strip.upcase.presence,
            title: (entry[:title] || entry["title"]).presence || "Amazon product",
            description: (entry[:description] || entry["description"]).to_s,
            market: (entry[:market] || entry["market"] || default_market).to_s,
            category: entry[:category] || entry["category"],
            image_url: entry[:image_url] || entry["image_url"],
            price_cents: entry[:price_cents] || entry["price_cents"],
            currency: entry[:currency] || entry["currency"],
          }
        else
          asin = entry.to_s.strip.upcase
          {
            asin:,
            title: "Amazon product #{asin}",
            description: "",
            market: default_market,
            category: nil,
            image_url: nil,
            price_cents: nil,
            currency: nil,
          }
        end
      end

      def upsert_row!(row, category:)
        return false if row[:external_id].blank? || row[:click_url].blank? || row[:title].blank?

        AffiliateProduct.upsert_from_feed!(
          source: "amazon",
          external_id: row[:external_id],
          title: row[:title],
          description: row[:description],
          merchant: row[:merchant] || "Amazon",
          program_id: partner_tag,
          price_cents: row[:price_cents],
          currency: row[:currency],
          image_url: row[:image_url],
          click_url: row[:click_url],
          category: category.presence || row[:category],
          market: Shared::AmazonMarketplace.country_for(market),
          in_stock: row.fetch(:in_stock, true),
          placeholder: false,
        )
        true
      end

      def search_items(keywords:, page:)
        payload = {
          "keywords" => keywords,
          "partnerTag" => partner_tag,
          "partnerType" => "Associates",
          "marketplace" => marketplace_host,
          "itemPage" => page,
          "resources" => DEFAULT_RESOURCES,
        }
        parse_search(post_catalog("/catalog/v1/searchItems", payload))
      end

      def get_items(asins)
        ids = Array(asins).map { |a| a.to_s.strip.upcase }.reject(&:blank?).first(10)
        return [] if ids.empty?

        payload = {
          "itemIds" => ids,
          "itemIdType" => "ASIN",
          "partnerTag" => partner_tag,
          "partnerType" => "Associates",
          "marketplace" => marketplace_host,
          "resources" => DEFAULT_RESOURCES,
        }
        parse_items(post_catalog("/catalog/v1/getItems", payload))
      end

      def post_catalog(path, payload)
        token = access_token
        uri = URI("#{API_BASE}#{path}")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = auth_header(token)
        req["Content-Type"] = "application/json"
        req["x-marketplace"] = marketplace_host
        req.body = JSON.generate(payload)

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 25) do |http|
          http.request(req)
        end
        body = JSON.parse(res.body)
        unless res.is_a?(Net::HTTPSuccess)
          msg = body.dig("message") || body.dig("errors", 0, "message") || res.code
          raise "Creators API #{path}: #{msg}"
        end
        body
      end

      def auth_header(token)
        if version.to_s.start_with?("2.")
          "Bearer #{token}, Version #{version}"
        else
          "Bearer #{token}"
        end
      end

      def access_token
        if defined?(Rails) && Rails.cache
          cached = Rails.cache.read(TOKEN_CACHE_KEY)
          return cached if cached.present?
        end

        endpoint = TOKEN_ENDPOINTS.fetch(version) do
          raise "Unknown AMAZON_CREATORS_VERSION=#{version} (expected #{TOKEN_ENDPOINTS.keys.join(', ')})"
        end
        uri = URI(endpoint)
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(
          grant_type: "client_credentials",
          client_id:,
          client_secret:,
          scope: "creatorsapi::default",
        )
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 15) do |http|
          http.request(req)
        end
        data = JSON.parse(res.body)
        token = data["access_token"]
        raise "Creators API token error: #{data['error'] || data['error_description'] || res.code}" if token.blank?

        ttl = [ (data["expires_in"].to_i - 60), 60 ].max
        Rails.cache.write(TOKEN_CACHE_KEY, token, expires_in: ttl.seconds) if defined?(Rails) && Rails.cache
        token
      end

      def parse_search(json)
        items = json.dig("searchResult", "items") ||
                json.dig("SearchResult", "Items") ||
                []
        Array(items).filter_map { |item| parse_item(item) }
      end

      def parse_items(json)
        items = json.dig("itemsResult", "items") ||
                json.dig("ItemsResult", "Items") ||
                []
        Array(items).filter_map { |item| parse_item(item) }
      end

      def parse_item(item)
        asin = (item["asin"] || item["ASIN"]).to_s
        return nil if asin.blank?

        # Prefer API detailPageURL (already tagged). Fall back to marketplace helper.
        click = (item["detailPageURL"] || item["DetailPageURL"]).to_s
        click = Shared::AmazonMarketplace.product_url(asin, market:) if click.blank?

        title = item.dig("itemInfo", "title", "displayValue") ||
                item.dig("ItemInfo", "Title", "DisplayValue") ||
                ""
        brand = item.dig("itemInfo", "byLineInfo", "brand", "displayValue") ||
                item.dig("ItemInfo", "ByLineInfo", "Brand", "DisplayValue") ||
                ""
        image = item.dig("images", "primary", "medium", "url") ||
                item.dig("images", "primary", "large", "url") ||
                item.dig("Images", "Primary", "Medium", "URL") ||
                ""

        listing = Array(item.dig("offersV2", "listings") || item.dig("Offers", "Listings")).first
        amount = listing&.dig("price", "amount") || listing&.dig("Price", "Amount")
        currency = listing&.dig("price", "currency") || listing&.dig("Price", "Currency")
        availability = listing&.dig("availability", "message") ||
                       listing&.dig("Availability", "Message").to_s

        {
          external_id: asin,
          title: title.to_s,
          description: brand.to_s,
          merchant: "Amazon",
          price_cents: amount ? (amount.to_f * 100).round : nil,
          currency: currency.to_s,
          image_url: image.to_s,
          click_url: click.to_s,
          category: nil,
          in_stock: availability !~ /unavailable|out of stock/i,
        }
      end

      def to_deal(row)
        Affiliate::Deal.new(
          title: row[:title],
          description: row[:description].to_s.truncate(120),
          price: row[:price_cents] ? format("%.2f", row[:price_cents] / 100.0) : "",
          currency: row[:currency].to_s,
          image_url: row[:image_url].to_s,
          click_url: row[:click_url].to_s,
          merchant: row[:merchant].to_s.presence || "Amazon",
          placeholder: false,
        )
      end
    end
  end
end
