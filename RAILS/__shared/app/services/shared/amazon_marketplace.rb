# frozen_string_literal: true

module Shared
  # Which Amazon storefront a click belongs to, and which tracking id it is
  # allowed to carry.
  #
  # Associates is licensed per marketplace, not per company: a tag issued for
  # amazon.de pays nothing on amazon.co.uk, and sending a German tag to a
  # British storefront is not a rounding error, it is an untracked click. So a
  # single global AMAZON_ASSOCIATE_TAG cannot serve a network of city sites
  # spread across countries — which is what pub4 is.
  #
  # It was worse than un-tracked before this existed: SeoKit#amazon_affiliate_url
  # built bare ASIN links against amazon.COM for every city, so a Bergen or
  # Stockholm reader was sent to a storefront that does not sell to them, using
  # a tag not registered there.
  #
  # Two separate facts are modelled here, because they are genuinely different:
  #
  #   STOREFRONTS — countries where Amazon actually operates a storefront.
  #   SERVED_BY   — countries where it does not, and which storefront serves
  #                 them instead. Norway, Denmark, Finland and Iceland have no
  #                 Amazon of their own; readers there buy from amazon.de or
  #                 amazon.co.uk. That is a commercial choice about shipping and
  #                 language, not a technical one, so it is written down
  #                 explicitly rather than guessed from geography.
  module AmazonMarketplace
    # country code => storefront host. Only real storefronts belong here.
    STOREFRONTS = {
      "US" => "amazon.com",
      "GB" => "amazon.co.uk",
      "IE" => "amazon.ie",
      "DE" => "amazon.de",
      "FR" => "amazon.fr",
      "IT" => "amazon.it",
      "ES" => "amazon.es",
      "NL" => "amazon.nl",
      "BE" => "amazon.com.be",
      "SE" => "amazon.se",
      "PL" => "amazon.pl",
    }.freeze

    # Countries with no storefront of their own => the storefront that serves
    # them. The Nordics route to Germany (ships north, broad catalogue); Iceland
    # routes to the UK, which is the historical shipping path.
    SERVED_BY = {
      "NO" => "DE",
      "DK" => "DE",
      "FI" => "DE",
      "IS" => "GB",
      "AT" => "DE",
      "CH" => "DE",
      "LU" => "DE",
      "PT" => "ES",
      "CZ" => "DE",
      "SK" => "DE",
      "HU" => "DE",
      "RO" => "DE",
      "GR" => "DE",
      "EE" => "DE",
      "LV" => "DE",
      "LT" => "DE",
      "SI" => "DE",
      "HR" => "DE",
      "BG" => "DE",
    }.freeze

    # PA-API is region-scoped and the regions do not follow the storefront TLD.
    # Only two matter for the marketplaces above.
    REGIONS = {
      "amazon.com" => "us-east-1",
    }.freeze
    DEFAULT_REGION = "eu-west-1"

    # The one marketplace used when a request carries no country at all — a
    # background job, a console, a city row missing its country_code. Germany
    # rather than the US because the overwhelming majority of pub4's cities are
    # European, so it is the least-wrong default.
    FALLBACK_COUNTRY = "DE"

    module_function

    # Normalises whatever the caller has — a City, a country code, nil — into a
    # storefront country code. Callers pass `city.country_code`, which is a
    # validated column, but jobs and mailers do not always have a city.
    def country_for(market)
      code = market.respond_to?(:country_code) ? market.country_code : market
      code = code.to_s.strip.upcase
      return FALLBACK_COUNTRY if code.empty?

      code = SERVED_BY.fetch(code, code)
      STOREFRONTS.key?(code) ? code : FALLBACK_COUNTRY
    end

    def host_for(market)
      STOREFRONTS.fetch(country_for(market))
    end

    def paapi_host_for(market)
      "webservices.#{host_for(market)}"
    end

    def region_for(market)
      REGIONS.fetch(host_for(market), DEFAULT_REGION)
    end

    # Per-marketplace tracking id, from AMAZON_ASSOCIATE_TAG_<CC>.
    #
    # There is deliberately NO global fallback. A tag from the wrong marketplace
    # does not degrade gracefully — Amazon accepts the link, drops the
    # attribution, and the click looks fine while paying nothing. Returning nil
    # instead means the link is built without a tag: still a working product
    # link, honestly untracked, and visible as a gap rather than hidden as
    # phantom revenue.
    def tag_for(market)
      ENV["AMAZON_ASSOCIATE_TAG_#{country_for(market)}"].to_s.strip.presence
    end

    def configured?(market)
      tag_for(market).present?
    end

    # Which marketplaces actually have a tag. Used by the disclosure partial and
    # by any report that needs to say what is live.
    def configured_countries
      STOREFRONTS.keys.select { |code| ENV["AMAZON_ASSOCIATE_TAG_#{code}"].to_s.strip.present? }
    end

    # Product URL for an ASIN in the marketplace that serves `market`, tagged if
    # a tag exists for it.
    def product_url(asin, market: nil)
      id = asin.to_s.strip
      return nil if id.empty?

      url = "https://www.#{host_for(market)}/dp/#{id}"
      tag = tag_for(market)
      tag ? "#{url}?tag=#{tag}" : url
    end

    # Re-tag an existing Amazon URL for the marketplace it is already pointing
    # at — NOT for the reader's own market. Rewriting the host would change
    # which storefront the product is on, and the ASIN may not exist there;
    # a dead link earns less than an untagged one.
    def retag_url(url)
      uri = URI.parse(url.to_s.strip)
      return url.to_s unless uri.host

      country = country_for_host(uri.host)
      return url.to_s if country.nil?

      tag = ENV["AMAZON_ASSOCIATE_TAG_#{country}"].to_s.strip
      return url.to_s if tag.empty?

      params = URI.decode_www_form(uri.query.to_s).to_h
      params["tag"] = tag
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError
      url.to_s
    end

    # amazon.co.uk, www.amazon.de, smile.amazon.com -> country code.
    def country_for_host(host)
      normalised = host.to_s.downcase.sub(/\A(?:www|smile)\./, "")
      STOREFRONTS.key(normalised)
    end
  end
end
