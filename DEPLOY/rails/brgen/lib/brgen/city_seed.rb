# frozen_string_literal: true

module Brgen
  class CitySeed
    CityRow = Data.define(:domain, :name, :country_code, :locale, :currency, :time_zone, :latitude, :longitude)

    ROWS = [
      CityRow.new("brgen.no", "Bergen", "NO", "nb", "NOK", "Europe/Oslo", 60.3913, 5.3221),
      CityRow.new("longyearbyn.no", "Longyearbyen", "NO", "nb", "NOK", "Arctic/Longyearbyen", 78.2232, 15.6267),
      CityRow.new("oshlo.no", "Oslo", "NO", "nb", "NOK", "Europe/Oslo", 59.9139, 10.7522),
      CityRow.new("stvanger.no", "Stavanger", "NO", "nb", "NOK", "Europe/Oslo", 58.9700, 5.7331),
      CityRow.new("trmso.no", "Tromsø", "NO", "nb", "NOK", "Europe/Oslo", 69.6492, 18.9553),
      CityRow.new("trndheim.no", "Trondheim", "NO", "nb", "NOK", "Europe/Oslo", 63.4305, 10.3951),
      CityRow.new("amstrdam.nl", "Amsterdam", "NL", "nl", "EUR", "Europe/Amsterdam", 52.3676, 4.9041),
      CityRow.new("lsangeles.com", "Los Angeles", "US", "en-US", "USD", "America/Los_Angeles", 34.0522, -118.2437)
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
        city.slug = row.name.parameterize
        city.time_zone = row.time_zone
        city.save!
      end
    end
  end
end
