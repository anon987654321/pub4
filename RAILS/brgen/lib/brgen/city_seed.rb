# frozen_string_literal: true

module Brgen
  class CitySeed
    CityRow = Data.define(:domain, :name, :country_code, :locale, :currency, :time_zone, :latitude, :longitude)

    # City data is driven from the authoritative list in DomainRegistry so that
    # every supported TLD/domain gets a proper City record for automatic resolution.
    # No city switcher UI exists — resolution is purely from the incoming host/TLD.
    def self.rows_from_registry
      return [] unless defined?(Brgen::DomainRegistry)

      Brgen::DomainRegistry::ENTRIES.map do |e|
        lat, lng = case e.domain
        when /brgen.no/ then [ 60.3913, 5.3221 ]
        when /oshlo.no/ then [ 59.9139, 10.7522 ]
        when /lsangeles.com/ then [ 34.0522, -118.2437 ]
        when /lndon.uk/ then [ 51.5074, -0.1278 ]
        else [ 0, 0 ]
        end
        tz = case e.domain
        when /\.no$|\.is$|\.dk$|\.se$|\.fi$/ then "Europe/Oslo"
        when /lsangeles|newyrk|austn|chcago|denvr|dllas|dtroit|houstn|mnnesota|prtland|wshingtondc/ then "America/Los_Angeles"
        else "UTC"
        end
        CityRow.new(e.domain, e.city, e.country, e.locale.to_s, e.currency, tz, lat, lng)
      end
    end

    ROWS = rows_from_registry.presence || [
      # Fallback minimal set if registry not loaded
      CityRow.new("brgen.no", "Bergen", "NO", "nb", "NOK", "Europe/Oslo", 60.3913, 5.3221),
      CityRow.new("lsangeles.com", "Los Angeles", "US", "en-US", "USD", "America/Los_Angeles", 34.0522, -118.2437),
    ].freeze

    def self.sync!
      ROWS.each { |row| sync_city(row) }
    end

    def self.sync_city(row)
      City.find_or_initialize_by(domain: row.domain).tap do |city|
        city.country_code = row.country_code
        city.currency = row.currency
        city.latitude = row.latitude
        city.locale = row.locale
        city.longitude = row.longitude
        city.name = row.name
        city.slug = row.domain.parameterize.presence || row.name.parameterize
        city.time_zone = row.time_zone
        city.save!
      end
    end
  end
end
