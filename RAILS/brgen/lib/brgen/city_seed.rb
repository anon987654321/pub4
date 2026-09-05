# frozen_string_literal: true

module Brgen
  class CitySeed
    CityRow = Data.define(:domain, :name, :country_code, :locale, :currency, :time_zone, :latitude, :longitude)

    # City-centre WGS84. Keyed by DomainRegistry domain so a new city without a
    # row raises at load rather than seeding on 0,0.
    COORDINATES = {
      "brgen.no" => [ 60.3913, 5.3221 ],
      "longyearbyn.no" => [ 78.2232, 15.6267 ],
      "oshlo.no" => [ 59.9139, 10.7522 ],
      "stvanger.no" => [ 58.9700, 5.7331 ],
      "trmso.no" => [ 69.6492, 18.9553 ],
      "trndheim.no" => [ 63.4305, 10.3951 ],
      "reykjavk.is" => [ 64.1466, -21.9426 ],
      "kbenhvn.dk" => [ 55.6761, 12.5683 ],
      "gtebrg.se" => [ 57.7089, 11.9746 ],
      "mlmoe.se" => [ 55.6050, 13.0038 ],
      "stholm.se" => [ 59.3293, 18.0686 ],
      "hlsinki.fi" => [ 60.1699, 24.9384 ],
      "brmingham.uk" => [ 52.4862, -1.8904 ],
      "cardff.uk" => [ 51.4816, -3.1791 ],
      "edinbrgh.uk" => [ 55.9533, -3.1883 ],
      "glasgw.uk" => [ 55.8642, -4.2518 ],
      "lndon.uk" => [ 51.5074, -0.1278 ],
      "lverpool.uk" => [ 53.4084, -2.9916 ],
      "mnchester.uk" => [ 53.4808, -2.2426 ],
      "amstrdam.nl" => [ 52.3676, 4.9041 ],
      "rottrdam.nl" => [ 51.9244, 4.4777 ],
      "utrcht.nl" => [ 52.0907, 5.1214 ],
      "brssels.be" => [ 50.8503, 4.3517 ],
      "zrich.ch" => [ 47.3769, 8.5417 ],
      "lchtenstein.li" => [ 47.1410, 9.5215 ],
      "frankfrt.de" => [ 50.1109, 8.6821 ],
      "brdeaux.fr" => [ 44.8378, -0.5792 ],
      "mrseille.fr" => [ 43.2965, 5.3698 ],
      "mlan.it" => [ 45.4642, 9.1900 ],
      "lisbon.pt" => [ 38.7223, -9.1393 ],
      "wrsawa.pl" => [ 52.2297, 21.0122 ],
      "gdnsk.pl" => [ 54.3520, 18.6466 ],
      "austn.us" => [ 30.2672, -97.7431 ],
      "chcago.us" => [ 41.8781, -87.6298 ],
      "denvr.us" => [ 39.7392, -104.9903 ],
      "dllas.us" => [ 32.7767, -96.7970 ],
      "dtroit.us" => [ 42.3314, -83.0458 ],
      "houstn.us" => [ 29.7604, -95.3698 ],
      "lsangeles.com" => [ 34.0522, -118.2437 ],
      "mnnesota.com" => [ 44.9778, -93.2650 ],
      "newyrk.us" => [ 40.7128, -74.0060 ],
      "prtland.com" => [ 45.5152, -122.6784 ],
      "wshingtondc.com" => [ 38.9072, -77.0369 ]
    }.freeze

    TIME_ZONES = {
      "brgen.no" => "Europe/Oslo",
      "longyearbyn.no" => "Arctic/Longyearbyen",
      "oshlo.no" => "Europe/Oslo",
      "stvanger.no" => "Europe/Oslo",
      "trmso.no" => "Europe/Oslo",
      "trndheim.no" => "Europe/Oslo",
      "reykjavk.is" => "Atlantic/Reykjavik",
      "kbenhvn.dk" => "Europe/Copenhagen",
      "gtebrg.se" => "Europe/Stockholm",
      "mlmoe.se" => "Europe/Stockholm",
      "stholm.se" => "Europe/Stockholm",
      "hlsinki.fi" => "Europe/Helsinki",
      "brmingham.uk" => "Europe/London",
      "cardff.uk" => "Europe/London",
      "edinbrgh.uk" => "Europe/London",
      "glasgw.uk" => "Europe/London",
      "lndon.uk" => "Europe/London",
      "lverpool.uk" => "Europe/London",
      "mnchester.uk" => "Europe/London",
      "amstrdam.nl" => "Europe/Amsterdam",
      "rottrdam.nl" => "Europe/Amsterdam",
      "utrcht.nl" => "Europe/Amsterdam",
      "brssels.be" => "Europe/Brussels",
      "zrich.ch" => "Europe/Zurich",
      "lchtenstein.li" => "Europe/Vaduz",
      "frankfrt.de" => "Europe/Berlin",
      "brdeaux.fr" => "Europe/Paris",
      "mrseille.fr" => "Europe/Paris",
      "mlan.it" => "Europe/Rome",
      "lisbon.pt" => "Europe/Lisbon",
      "wrsawa.pl" => "Europe/Warsaw",
      "gdnsk.pl" => "Europe/Warsaw",
      "austn.us" => "America/Chicago",
      "chcago.us" => "America/Chicago",
      "denvr.us" => "America/Denver",
      "dllas.us" => "America/Chicago",
      "dtroit.us" => "America/Detroit",
      "houstn.us" => "America/Chicago",
      "lsangeles.com" => "America/Los_Angeles",
      "mnnesota.com" => "America/Chicago",
      "newyrk.us" => "America/New_York",
      "prtland.com" => "America/Los_Angeles",
      "wshingtondc.com" => "America/New_York"
    }.freeze

    # City data is driven from the authoritative list in DomainRegistry so that
    # every supported TLD/domain gets a proper City record for automatic resolution.
    # No city switcher UI exists — resolution is purely from the incoming host/TLD.
    def self.rows_from_registry
      return [] unless defined?(Brgen::DomainRegistry)

      Brgen::DomainRegistry::ENTRIES.map do |e|
        lat, lng = COORDINATES.fetch(e.domain)
        CityRow.new(e.domain, e.city, e.country, e.locale.to_s, e.currency, TIME_ZONES.fetch(e.domain), lat, lng)
      end
    end

    ROWS = rows_from_registry.presence || [
      # Fallback minimal set if registry not loaded
      CityRow.new("brgen.no", "Bergen", "NO", "nb", "NOK", "Europe/Oslo", 60.3913, 5.3221),
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
        city.slug = row.domain.parameterize.presence || row.name.parameterize
        city.time_zone = row.time_zone
        city.save!
      end
    end
  end
end
