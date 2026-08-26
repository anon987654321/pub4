# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "uri"
require_relative "tradedoubler_parsing"

# TradeDoubler partner-marketing client (publisher side).
#
# STATUS: live calls need an approved publisher site + programme connections +
# TRADEDOUBLER_TOKEN (PRODUCTS system token). Without a token every write path
# is a no-op and every read path prefers AffiliateProduct / placeholders.
#
# Official Products API uses matrix URIs and requires a feed id (fid):
#   GET https://api.tradedoubler.com/1.0/products.json;fid={id};page=1;pageSize=100?token=…
# Feeds are listed via productFeeds. Bulk: productsUnlimited + lastUpdated.
#
# Tokens (Account → Manage tokens): PRODUCTS, VOUCHERS, CONVERSIONS. Website ID
# for Link Converter is separate (TRADEDOUBLER_WEBSITE_ID).
module Shared
  module Tradedoubler
    BASE = "https://api.tradedoubler.com/1.0"
    LINK_CONVERTER_URL = "https://link.tradedoubler.com/lc"
    PAGE_SIZE = 100
    MAX_PAGES = 20
    # Search service hard-caps at 1000 products per the docs.
    SEARCH_HARD_CAP = 1_000

    Deal = Data.define(:title, :description, :price, :currency, :image_url, :click_url, :merchant, :placeholder)
    Voucher = Data.define(
      :external_id, :program_id, :program_name, :code, :title, :short_description,
      :description, :voucher_type_id, :track_url, :landing_url, :discount_amount,
      :percentage, :site_specific, :exclusive, :currency, :starts_at, :ends_at
    )
    Feed = Data.define(:feed_id, :name, :active, :currency, :language, :product_count, :program_ids, :last_modified)

    # Response shapes live next door; see tradedoubler_parsing.rb.
    extend TradedoublerParsing

    class << self
      def products_token
        ENV["TRADEDOUBLER_PRODUCTS_TOKEN"].presence || ENV["TRADEDOUBLER_TOKEN"].presence
      end

      def vouchers_token
        ENV["TRADEDOUBLER_VOUCHERS_TOKEN"].presence || products_token
      end

      def conversions_token
        ENV["TRADEDOUBLER_CONVERSIONS_TOKEN"].presence
      end

      # Link Converter lives in Shared::LinkConverter so amber can attribute too.
      # These delegate rather than keeping a second copy of an attribution rule:
      # two copies is how one of them silently stops attributing.
      def website_id = Shared::LinkConverter.website_id

      def token = products_token
      def market = ENV.fetch("TRADEDOUBLER_MARKET", "NO")
      def configured? = products_token.present?
      def vouchers_configured? = vouchers_token.present?
      def link_converter_configured? = Shared::LinkConverter.configured?

      # Comma-separated feed IDs. When blank, import discovers active feeds.
      def feed_ids
        raw = ENV["TRADEDOUBLER_FEED_IDS"].to_s
        raw.split(/[,\s]+/).map(&:strip).reject(&:empty?).map(&:to_i).reject(&:zero?)
      end

      def import_mode
        ENV.fetch("TRADEDOUBLER_IMPORT_MODE", "search") # search | unlimited
      end

      # --- Read path for views -------------------------------------------------

      def deals(category: nil, limit: 8)
        stored = stored_deals(category:, limit:)
        return stored if stored.any?
        return [] unless configured?

        Rails.cache.fetch(cache_key("deals", category, limit), expires_in: cache_ttl_for(:search_results)) do
          fetch_deals(category:, limit:)
        end
      end

      def stored_deals(category: nil, limit: 8)
        return [] unless AffiliateProduct.table_exists?

        AffiliateProduct.sellable
                        .for_market(market)
                        .for_category(category)
                        .limit(limit)
                        .map { |product| to_deal(product) }
      # AffiliateProduct.table_exists? is checked on the way in, so this cannot be
      # the missing-table case. What is left is a schema fault — a column the
      # scope names and the table has not got, a migration half-applied — and
      # returning [] for that is a shop page that is quietly empty forever.
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("tradedoubler deals: #{e.class}: #{e.message}")
        []
      end

      def vouchers(limit: 20, site_specific: false, program_id: nil)
        stored = stored_vouchers(limit:, site_specific:)
        return stored if stored.any?
        return [] unless vouchers_configured?

        Rails.cache.fetch(cache_key("vouchers", limit, site_specific, program_id),
expires_in: cache_ttl_for(:search_results)) do
          fetch_vouchers(limit:, site_specific:, program_id:)
        end
      end

      def stored_vouchers(limit: 20, site_specific: false)
        return [] unless defined?(AffiliateVoucher) && AffiliateVoucher.table_exists?

        scope = AffiliateVoucher.live.order(ends_at: :asc)
        scope = scope.where(site_specific: true) if site_specific
        scope.limit(limit).map(&:to_struct)
      # Same shape as deals above: the table check is already done on the way in.
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("tradedoubler vouchers: #{e.class}: #{e.message}")
        []
      end

      # --- Write path: product import ------------------------------------------

      def import!(category: nil, pages: MAX_PAGES)
        return 0 unless configured?

        ids = resolve_feed_ids
        return 0 if ids.empty?

        written = 0
        ids.each do |fid|
          written += if import_mode == "unlimited"
                       import_unlimited!(fid, category:)
          else
                       import_search!(fid, category:, pages:)
          end
        end
        written
      end

      def import_vouchers!(limit: 1_000)
        return 0 unless vouchers_configured?
        return 0 unless defined?(AffiliateVoucher) && AffiliateVoucher.table_exists?

        rows = fetch_vouchers(limit:, site_specific: false, program_id: nil, persist: false)
        rows.count do |row|
          AffiliateVoucher.upsert_from_api!(row)
          true
        end
      end

      # --- Feeds ---------------------------------------------------------------

      def list_feeds
        return [] unless configured?

        body = get_json(matrix_uri("productFeeds", matrix: {}, token: products_token))
        Array(body.is_a?(Hash) ? body["feeds"] : body).filter_map do |feed|
          next unless feed.is_a?(Hash)

          Feed.new(
            feed_id: feed["feedId"].to_i,
            name: feed["name"].to_s,
            active: feed["active"] != false,
            currency: feed["currencyISOCode"].to_s,
            language: feed["languageISOCode"].to_s,
            product_count: feed["numberOfProducts"].to_i,
            program_ids: Array(feed["programs"]).filter_map { |p| p.is_a?(Hash) ? p["programId"] : nil },
            last_modified: feed["lastModifiedTime"].to_s,
          )
        end
      rescue StandardError => e
        Ground::Swallow.log(e, context: "Tradedoubler.list_feeds") if defined?(Ground::Swallow)
        []
      end

      def resolve_feed_ids
        configured = feed_ids
        return configured if configured.any?

        list_feeds.select(&:active).map(&:feed_id).reject(&:zero?)
      end

      def feed_last_updated(fid)
        body = get_json(matrix_uri("productsUnlimited/lastUpdated", matrix: { fid: }, token: products_token))
        return nil unless body.is_a?(Hash)

        body["lastUpdatedTime"]
      rescue StandardError # scan: intentional — an unparseable upstream value is absent, not fatal
        nil
      end

      # --- HTTP + parse --------------------------------------------------------

      def fetch_page(fid:, category: nil, page: 1, page_size: PAGE_SIZE)
        matrix = {
          fid:,
          page:,
          pageSize: page_size,
          limit: [ page * page_size, SEARCH_HARD_CAP ].min,
        }
        matrix[:category] = category if category.present?
        matrix[:language] = language_param if language_param.present?

        body = get_json(matrix_uri("products", matrix:, token: products_token))
        parse(body)
      end

      def fetch_unlimited(fid:)
        body = get_json(matrix_uri("productsUnlimited", matrix: { fid: }, token: products_token))
        parse(body)
      end

      def fetch_deals(category:, limit:)
        ids = resolve_feed_ids
        return [] if ids.empty?

        rows = []
        ids.each do |fid|
          rows.concat(fetch_page(fid:, category:, page: 1))
          break if rows.size >= limit
        end
        rows.first(limit).map { |row| row_to_deal(row) }
      end

      def fetch_vouchers(limit: 20, site_specific: false, program_id: nil, persist: true)
        matrix = { pageSize: limit, page: 1, dateOutputFormat: "iso8601" }
        matrix[:siteSpecific] = true if site_specific
        matrix[:programId] = program_id if program_id.present?

        body = get_json(matrix_uri("vouchers", matrix:, token: vouchers_token))
        list = body.is_a?(Array) ? body : Array(body.is_a?(Hash) ? body["vouchers"] || body["voucher"] : nil)
        list.filter_map { |raw| parse_voucher(raw) }
      rescue StandardError => e
        Ground::Swallow.log(e, context: "Tradedoubler.fetch_vouchers") if defined?(Ground::Swallow)
        []
      end


      # EPI helpers for tracked surfaces (appended by views / Link Converter).
      def epi_for(**parts) = Shared::LinkConverter.epi_for(**parts)

      def append_epi(url, epi:, epi2: nil) = Shared::LinkConverter.append_epi(url, epi:, epi2:)

      def link_converter_remote_url = Shared::LinkConverter.remote_script_url

      # Download server-side Link Converter script (ad-block resistant path).
      def sync_link_converter!(local_path:) = Shared::LinkConverter.sync!(local_path:)

      def matrix_uri(path, matrix:, token:, extension: "json")
        matrix_part = matrix.compact.map do |key, value|
          Array(value).map { |v| "#{key}=#{CGI.escape(v.to_s)}" }
        end.flatten.join(";")
        suffix = matrix_part.empty? ? "" : ";#{matrix_part}"
        ext = extension.present? ? ".#{extension}" : ""
        uri = URI("#{BASE}/#{path}#{ext}#{suffix}")
        uri.query = URI.encode_www_form(token:)
        uri
      end

      def get_json(uri)
        res = Net::HTTP.get_response(uri)
        return nil unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      rescue JSON::ParserError, StandardError => e
        Ground::Swallow.log(e, context: "Tradedoubler.get_json") if defined?(Ground::Swallow)
        nil
      end

      def language_param
        ENV["TRADEDOUBLER_LANGUAGE"].presence # e.g. nb, no, en
      end

      def cache_key(*parts)
        ([ "td", market ] + parts.map(&:to_s)).join("_")
      end

      def cache_ttl_for(key_type)
        if defined?(Shared::CachePolicy)
          Shared::CachePolicy.ttl_for(key_type)
        else
          { search_results: 15.minutes }.fetch(key_type.to_sym, 15.minutes)
        end
      end

      private

      def import_search!(fid, category:, pages:)
        written = 0
        (1..pages).each do |page|
          break if page * PAGE_SIZE > SEARCH_HARD_CAP

          rows = fetch_page(fid:, category:, page:)
          break if rows.empty?

          written += upsert_rows(rows, category:)
          break if rows.size < PAGE_SIZE
        end
        written
      end

      def import_unlimited!(fid, category:)
        updated = feed_last_updated(fid)
        cache_key_lu = "td_unlimited_lu_#{fid}"
        if updated.present? && Rails.cache.read(cache_key_lu) == updated
          return 0
        end

        rows = fetch_unlimited(fid:)
        written = upsert_rows(rows, category:)
        Rails.cache.write(cache_key_lu, updated, expires_in: 48.hours) if updated.present?
        written
      end

      def upsert_rows(rows, category:)
        written = 0
        rows.each do |row|
          external_id = row[:external_id]
          next if external_id.blank? || row[:click_url].blank? || row[:title].blank?

          AffiliateProduct.upsert_from_feed!(
            source: "tradedoubler",
            external_id:,
            title: row[:title],
            description: row[:description],
            merchant: row[:merchant],
            program_id: row[:program_id],
            price_cents: row[:price_cents],
            currency: row[:currency],
            image_url: row[:image_url],
            click_url: row[:click_url],
            category: category.presence || row[:category],
            market:,
            in_stock: row[:in_stock],
            placeholder: false,
          )
          written += 1
        end
        written
      end

      def parse_voucher(raw)
        return nil unless raw.is_a?(Hash)

        id = (raw["id"] || raw["voucherId"]).to_s.presence
        return nil if id.blank?

        Voucher.new(
          external_id: id,
          program_id: raw["programId"].to_s.presence,
          program_name: raw["programName"].to_s,
          code: raw["code"].to_s,
          title: raw["title"].to_s,
          short_description: raw["shortDescription"].to_s,
          description: raw["description"].to_s,
          voucher_type_id: raw["voucherTypeId"].to_i,
          track_url: (raw["defaultTrackUri"] || raw["defaultTrackURL"]).to_s,
          landing_url: raw["landingUrl"].to_s,
          discount_amount: raw["discountAmount"],
          percentage: raw["isPercentage"] == true || raw["isPercentage"].to_s == "true",
          site_specific: raw["siteSpecific"] == true || raw["exclusive"] == true,
          exclusive: raw["exclusive"] == true,
          currency: raw["currencyId"].to_s,
          starts_at: parse_td_time(raw["startDate"] || raw["publishStartDate"]),
          ends_at: parse_td_time(raw["endDate"] || raw["publishEndDate"]),
        )
      end

      def parse_td_time(value)
        return nil if value.blank?
        return Time.zone.at(value.to_i / 1000.0) if value.to_s.match?(/\A\d{10,}\z/)

        Time.zone.parse(value.to_s)
      rescue StandardError # scan: intentional — an unparseable upstream timestamp is absent, not fatal
        nil
      end
    end
  end
end
