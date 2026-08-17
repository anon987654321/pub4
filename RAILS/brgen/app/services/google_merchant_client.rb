# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "time"

# Thin Google Merchant API (products v1) client — no google-cloud gem.
#
# Targets productInputs.insert / patch / delete and products.get for status.
# Content API for Shopping is retired; do not call shoppingcontent.googleapis.com.
#
# Auth: OAuth2 access token from a service account or user refresh token.
# Preferred on the VPS: short-lived access token minted by a small helper that
# reads GOOGLE_MERCHANT_SERVICE_ACCOUNT_JSON (or pre-minted GOOGLE_MERCHANT_ACCESS_TOKEN).
#
# Required ENV:
#   GOOGLE_MERCHANT_ACCOUNT_ID     — Merchant Center account id (numeric)
#   GOOGLE_MERCHANT_DATASOURCE_ID  — API primary data source id
#   GOOGLE_MERCHANT_ACCESS_TOKEN  — Bearer token (or implement token mint below)
#
# Optional:
#   GOOGLE_MERCHANT_CONTENT_LANGUAGE  default "nb"
#   GOOGLE_MERCHANT_FEED_LABEL        default "NO"
module GoogleMerchantClient
  API_ROOT = "https://merchantapi.googleapis.com/products/v1"
  SCOPE = "https://www.googleapis.com/auth/content"

  NotConfigured = Class.new(StandardError)
  ApiError = Class.new(StandardError)

  class << self
    def account_id   = ENV["GOOGLE_MERCHANT_ACCOUNT_ID"].to_s.strip.presence
    def datasource_id = ENV["GOOGLE_MERCHANT_DATASOURCE_ID"].to_s.strip.presence
    def access_token = ENV["GOOGLE_MERCHANT_ACCESS_TOKEN"].to_s.strip.presence
    def content_language = ENV.fetch("GOOGLE_MERCHANT_CONTENT_LANGUAGE", "nb")
    def feed_label = ENV.fetch("GOOGLE_MERCHANT_FEED_LABEL", "NO")

    def configured?
      account_id.present? && datasource_id.present? && access_token.present?
    end

    def data_source_name
      "accounts/#{account_id}/dataSources/#{datasource_id}"
    end

    # Insert or replace a product input.
    # attrs: Hash with symbol keys matching productAttributes + offer_id
    def insert_product!(offer_id:, attributes:)
      raise NotConfigured, "Google Merchant" unless configured?

      body = {
        "offerId" => offer_id.to_s,
        "contentLanguage" => content_language,
        "feedLabel" => feed_label,
        "productAttributes" => camelize_attributes(attributes)
      }
      post(
        "/accounts/#{account_id}/productInputs:insert",
        body,
        query: { "dataSource" => data_source_name }
      )
    end

    # Partial update. update_paths are productAttributes paths, e.g.
    # %w[price availability title]
    def patch_product!(offer_id:, attributes:, update_paths:)
      raise NotConfigured, "Google Merchant" unless configured?

      name = product_input_name(offer_id)
      mask = Array(update_paths).map { |p| "productAttributes.#{camelize_key(p)}" }.join(",")
      body = {
        "name" => name,
        "productAttributes" => camelize_attributes(attributes)
      }
      patch(
        "/accounts/#{account_id}/productInputs/#{name.split('/').last}",
        body,
        query: {
          "updateMask" => mask,
          "dataSource" => data_source_name
        }
      )
    end

    def delete_product!(offer_id)
      raise NotConfigured, "Google Merchant" unless configured?

      name = product_input_name(offer_id)
      delete(
        "/accounts/#{account_id}/productInputs/#{name.split('/').last}",
        query: { "dataSource" => data_source_name }
      )
    end

    # Read-only processed product (status after Google rules).
    def get_product(offer_id)
      raise NotConfigured, "Google Merchant" unless configured?

      product_id = "#{content_language}~#{feed_label}~#{offer_id}"
      get("/accounts/#{account_id}/products/#{product_id}")
    end

    def product_input_name(offer_id)
      # Resource name uses contentLanguage~feedLabel~offerId
      "accounts/#{account_id}/productInputs/#{content_language}~#{feed_label}~#{offer_id}"
    end

    private

    def camelize_key(key)
      key.to_s.split("_").inject { |m, p| m + p.capitalize } || key.to_s
    end

    def camelize_attributes(attrs)
      out = {}
      attrs.each do |k, v|
        next if v.nil?

        ck = camelize_key(k)
        out[ck] =
          case v
          when Hash then camelize_attributes(v)
          when Array then v.map { |i| i.is_a?(Hash) ? camelize_attributes(i) : i }
          else v
          end
      end
      out
    end

    def get(path, query: {})
      request(:get, path, query: query)
    end

    def post(path, body, query: {})
      request(:post, path, body: body, query: query)
    end

    def patch(path, body, query: {})
      request(:patch, path, body: body, query: query)
    end

    def delete(path, query: {})
      request(:delete, path, query: query)
    end

    def request(method, path, body: nil, query: {})
      uri = URI("#{API_ROOT}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?

      req =
        case method
        when :get    then Net::HTTP::Get.new(uri)
        when :post   then Net::HTTP::Post.new(uri)
        when :patch  then Net::HTTP::Patch.new(uri)
        when :delete then Net::HTTP::Delete.new(uri)
        else raise ArgumentError, method.to_s
        end

      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body) if body

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(req)
      end

      parsed = res.body.to_s.empty? ? {} : JSON.parse(res.body)
      unless res.is_a?(Net::HTTPSuccess)
        msg = parsed.dig("error", "message") || parsed["message"] || res.code
        raise ApiError, "Merchant API #{method.upcase} #{path}: #{msg}"
      end
      parsed
    end
  end
end
