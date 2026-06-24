# frozen_string_literal: true

require "net/http"
require "json"

module Tradedoubler
  TOKEN   = ENV.fetch("TRADEDOUBLER_TOKEN", "")
  BASE    = "https://api.tradedoubler.com/1.0"

  Deal = Data.define(:title, :description, :price, :currency, :image_url, :click_url, :merchant)

  def self.deals(category: nil, limit: 8)
    return [] if TOKEN.blank?
    Rails.cache.fetch(cache_key(category), expires_in: cache_ttl_for(:search_results)) do
      fetch_deals(category:, limit:)
    end
  end

  def self.fetch_deals(category:, limit:)
    params = { token: TOKEN, limit: limit, format: "json" }
    params[:category] = category if category.present?
    uri = URI("#{BASE}/products")
    uri.query = URI.encode_www_form(params)
    res = Net::HTTP.get_response(uri)
    return [] unless res.is_a?(Net::HTTPSuccess)
    parse(JSON.parse(res.body))
  rescue StandardError => e
    Ground::Swallow.log(e, context: "Tradedoubler.fetch_deals")
    []
  end

  def self.parse(body)
    items = body.dig("products", "product") || []
    Array(items).map do |p|
      Deal.new(
        title:       p["name"].to_s,
        description: p["description"].to_s.truncate(120),
        price:       p.dig("fields", "Price").to_s,
        currency:    p.dig("fields", "Currency").to_s,
        image_url:   p["imageUrl"].to_s,
        click_url:   p["clickUrl"].to_s,
        merchant:    p.dig("program", "name").to_s
      )
    end
  end

  def self.cache_key(category)
    [ "td_deals", category.to_s ].join("_")
  end

  def self.cache_ttl_for(key_type)
    if defined?(Shared::CachePolicy)
      Shared::CachePolicy.ttl_for(key_type)
    else
      { search_results: 15.minutes }.fetch(key_type.to_sym)
    end
  end
end
