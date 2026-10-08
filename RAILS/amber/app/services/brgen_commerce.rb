# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class BrgenCommerce
  Product = Data.define(
    :id, :title, :description, :merchant, :category, :price_cents, :currency,
    :condition, :availability, :delivery, :trust, :url, :image_url, :reasons, :metadata
  )

  DEFAULT_ENDPOINT = "https://markedsplass.brgen.no/catalog.json".freeze
  CACHE_TTL = 5.minutes
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 4

  class << self
    def search(item:, limit: 6)
      query = item.title.to_s.strip
      query = [ item.brand, item.category ].compact.join(" ").strip if query.blank?
      return [] if query.blank?

      payload = Rails.cache.fetch(cache_key(query, limit), expires_in: CACHE_TTL) do
        fetch_json(query, limit)
      end

      Array(payload["items"]).filter_map { |row| build_product(row) }
    rescue StandardError => e
      Rails.logger.warn("brgen commerce lookup failed: #{e.class}: #{e.message}")
      []
    end

    def endpoint
      ENV.fetch("BRGEN_MARKETPLACE_CATALOG_URL", DEFAULT_ENDPOINT)
    end

    def available?
      uri = URI.parse(endpoint)
      uri.is_a?(URI::HTTP) && (uri.scheme == "https" || Rails.env.development? || Rails.env.test?)
    rescue URI::InvalidURIError
      false
    end

    private

    def cache_key(query, limit)
      ["amber", "brgen-commerce", query.downcase, limit.to_i]
    end

    def fetch_json(query, limit)
      return { "items" => [] } unless available?

      uri = URI.parse(endpoint)
      uri.query = URI.encode_www_form(q: query, limit: limit)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "pub4-amber-commerce-v1"

      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(request) }

      return { "items" => [] } unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def build_product(row)
      Product.new(
        row["id"].to_s,
        row["title"].to_s,
        row["description"].to_s,
        row.dig("seller", "name").to_s.presence || "BRGEN",
        row.dig("category", "name").to_s,
        row.dig("price", "cents").to_i,
        row.dig("price", "currency").to_s.presence || "NOK",
        row["condition"].to_s,
        row["availability"] || {},
        row["delivery"] || {},
        row["trust"] || {},
        row["url"].to_s,
        row["image_url"].to_s.presence,
        Array(row["reasons"]),
        row["metadata"] || {}
      )
    end
  end
end
