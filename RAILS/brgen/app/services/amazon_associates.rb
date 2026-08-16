# frozen_string_literal: true

require "net/http"
require "json"
require "openssl"
require "time"

# Amazon Associates (Product Advertising API v5) product feed.
#
# STATUS: not yet enabled. AffiliateProduct::SOURCES has listed "amazon" since
# the table was created, but nothing ever wrote those rows — this is the
# adapter that will. It follows Tradedoubler's contract exactly (configured?,
# deals, import!) so Affiliate::NETWORKS can treat the two interchangeably.
#
# Approval is manual and cannot be automated from here:
#
#   1. Join the Associates programme for the target locale. Norway has no
#      Amazon storefront, so brgen sells against amazon.de or amazon.co.uk —
#      which is a commercial decision, not a config one.
#   2. Make three qualifying sales within 180 days, or the account is closed
#      and the tag stops paying.
#   3. Only then does Amazon issue PA-API credentials. A brand-new account has
#      an Associates tag but *no* API access, so this returns [] for a while
#      even after you are technically "in".
#
# Set AMAZON_ACCESS_KEY, AMAZON_SECRET_KEY, AMAZON_PARTNER_TAG and optionally
# AMAZON_HOST/AMAZON_REGION, then `rake affiliate:import`.
#
# UNVERIFIED: the SearchItems response shape below is written from Amazon's
# published schema, not from a live call, because a live call needs credentials
# nobody has yet. `parse` is deliberately tolerant of a missing Items key
# rather than betting the import on one shape.
module AmazonAssociates
  # PA-API is host- and region-specific per marketplace. de/eu-west-1 is the
  # closest storefront to Norway that ships here.
  DEFAULT_HOST = "webservices.amazon.de"
  DEFAULT_REGION = "eu-west-1"
  SERVICE = "ProductAdvertisingAPI"
  PAGE_SIZE = 10 # PA-API SearchItems hard cap
  MAX_PAGES = 10 # PA-API refuses ItemPage > 10

  class << self
    def access_key  = ENV["AMAZON_ACCESS_KEY"].presence
    def secret_key  = ENV["AMAZON_SECRET_KEY"].presence
    def partner_tag = ENV["AMAZON_PARTNER_TAG"].presence
    def host        = ENV.fetch("AMAZON_HOST", DEFAULT_HOST)
    def region      = ENV.fetch("AMAZON_REGION", DEFAULT_REGION)
    def market      = ENV.fetch("AMAZON_MARKET", "DE")

    def configured? = access_key.present? && secret_key.present? && partner_tag.present?

    # Same contract as Tradedoubler.deals: table first, live only as fallback.
    def deals(category: nil, limit: 8)
      return [] unless configured?

      Rails.cache.fetch("amazon/deals/#{category}/#{limit}", expires_in: 15.minutes) do
        search(category: category, page: 1).first(limit).map { |row| to_deal(row) }
      end
    rescue StandardError => e
      Rails.logger.warn("amazon_associates: #{e.class}: #{e.message}")
      []
    end

    def import!(category: nil, pages: MAX_PAGES)
      return 0 unless configured?

      written = 0
      (1..pages).each do |page|
        rows = search(category: category, page: page)
        break if rows.empty?

        rows.each do |row|
          # Without an ASIN there is no upsert key and a re-import would
          # duplicate the row on every run.
          next if row[:external_id].blank? || row[:click_url].blank? || row[:title].blank?

          AffiliateProduct.upsert_from_feed!(
            source: "amazon",
            external_id: row[:external_id],
            title: row[:title],
            description: row[:description],
            merchant: row[:merchant],
            program_id: partner_tag,
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
    rescue StandardError => e
      Rails.logger.warn("amazon_associates import: #{e.class}: #{e.message}")
      written.to_i
    end

    private

    def search(category:, page:)
      payload = {
        "Keywords" => category.presence || "deals",
        "PartnerTag" => partner_tag,
        "PartnerType" => "Associates",
        "Marketplace" => "www.#{host.sub("webservices.", "")}",
        "ItemPage" => page,
        "Resources" => %w[
          Images.Primary.Medium
          ItemInfo.Title
          ItemInfo.ByLineInfo
          Offers.Listings.Price
          Offers.Listings.Availability.Message
        ]
      }
      parse(post("SearchItems", payload))
    end

    def post(operation, payload)
      body = JSON.generate(payload)
      target = "com.amazon.paapi5.v1.#{SERVICE}v1.#{operation}"
      uri = URI("https://#{host}/paapi5/#{operation.downcase}")
      headers = signed_headers(operation: operation, target: target, body: body, uri: uri)

      response = Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.post(uri.path, body, headers)
      end
      return {} unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end

    # AWS SigV4. Written out rather than pulled from the aws-sdk: this is the
    # only AWS call in the app and the gem is ~30MB of transitive dependencies
    # on a 1GB host.
    def signed_headers(operation:, target:, body:, uri:)
      now = Time.now.utc
      amz_date = now.strftime("%Y%m%dT%H%M%SZ")
      date = now.strftime("%Y%m%d")
      payload_hash = OpenSSL::Digest::SHA256.hexdigest(body)

      canonical_headers =
        "content-encoding:amz-1.0\n" \
        "host:#{host}\n" \
        "x-amz-date:#{amz_date}\n" \
        "x-amz-target:#{target}\n"
      signed = "content-encoding;host;x-amz-date;x-amz-target"
      canonical = [ "POST", uri.path, "", canonical_headers, signed, payload_hash ].join("\n")

      scope = "#{date}/#{region}/#{SERVICE.downcase}/aws4_request"
      to_sign = [ "AWS4-HMAC-SHA256", amz_date, scope, OpenSSL::Digest::SHA256.hexdigest(canonical) ].join("\n")

      key = [ "AWS4#{secret_key}", date, region, SERVICE.downcase, "aws4_request" ]
            .reduce { |acc, part| OpenSSL::HMAC.digest("SHA256", acc, part) }
      signature = OpenSSL::HMAC.hexdigest("SHA256", key, to_sign)

      {
        "content-encoding" => "amz-1.0",
        "content-type" => "application/json; charset=utf-8",
        "host" => host,
        "x-amz-date" => amz_date,
        "x-amz-target" => target,
        "Authorization" => "AWS4-HMAC-SHA256 Credential=#{access_key}/#{scope}, " \
                           "SignedHeaders=#{signed}, Signature=#{signature}"
      }
    end

    def parse(json)
      Array(json.dig("SearchResult", "Items")).filter_map do |item|
        listing = item.dig("Offers", "Listings")&.first
        amount = listing&.dig("Price", "Amount")
        {
          external_id: item["ASIN"].to_s,
          title: item.dig("ItemInfo", "Title", "DisplayValue").to_s,
          description: item.dig("ItemInfo", "ByLineInfo", "Brand", "DisplayValue").to_s,
          merchant: "Amazon",
          price_cents: amount ? (amount.to_f * 100).round : nil,
          currency: listing&.dig("Price", "Currency").to_s,
          image_url: item.dig("Images", "Primary", "Medium", "URL").to_s,
          # DetailPageURL already carries the partner tag; never rebuild it by
          # hand or the click stops being attributed and stops paying.
          click_url: item["DetailPageURL"].to_s,
          category: nil,
          in_stock: listing&.dig("Availability", "Message").to_s !~ /unavailable/i
        }
      end
    end

    def to_deal(row)
      Affiliate::Deal.new(
        title: row[:title],
        description: row[:description].to_s.truncate(120),
        price: row[:price_cents] ? format("%.2f", row[:price_cents] / 100.0) : "",
        currency: row[:currency],
        image_url: row[:image_url],
        click_url: row[:click_url],
        merchant: row[:merchant],
        placeholder: false
      )
    end
  end
end
