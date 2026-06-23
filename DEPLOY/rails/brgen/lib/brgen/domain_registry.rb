# frozen_string_literal: true

module Brgen
  class DomainRegistry
    Entry = Data.define(:domain, :city, :country, :locale, :currency, :marketplace_subdomain)
    Result = Data.define(:entry, :city_record, :subapp, :host)

    class UnknownHost < StandardError; end
    class UnknownSubdomain < StandardError; end

    SUBAPP_ALIASES = {
      "ai" => :ai,
      "dating" => :dating,
      "maps" => :maps,
      "playlist" => :playlist,
      "takeaway" => :takeaway,
      "tv" => :tv,
      "marche" => :marketplace,
      "markadur" => :marketplace,
      "markedsplads" => :marketplace,
      "markedsplass" => :marketplace,
      "marketplace" => :marketplace,
      "markkinapaikka" => :marketplace,
      "marknadsplats" => :marketplace,
      "marktplaats" => :marketplace,
      "marktplatz" => :marketplace,
      "mercado" => :marketplace,
      "mercato" => :marketplace
    }.freeze

    LOCAL_HOSTS = ["127.0.0.1", "localhost"].freeze

    ENTRIES = [
      Entry.new("brgen.no", "Bergen", "NO", :nb, "NOK", "markedsplass"),
      Entry.new("longyearbyn.no", "Longyearbyen", "NO", :nb, "NOK", "markedsplass"),
      Entry.new("oshlo.no", "Oslo", "NO", :nb, "NOK", "markedsplass"),
      Entry.new("stvanger.no", "Stavanger", "NO", :nb, "NOK", "markedsplass"),
      Entry.new("trmso.no", "Tromsø", "NO", :nb, "NOK", "markedsplass"),
      Entry.new("trndheim.no", "Trondheim", "NO", :nb, "NOK", "markedsplass"),
      Entry.new("reykjavk.is", "Reykjavik", "IS", :is, "ISK", "markadur"),
      Entry.new("kbenhvn.dk", "København", "DK", :da, "DKK", "markedsplads"),
      Entry.new("gtebrg.se", "Göteborg", "SE", :sv, "SEK", "marknadsplats"),
      Entry.new("mlmoe.se", "Malmö", "SE", :sv, "SEK", "marknadsplats"),
      Entry.new("stholm.se", "Stockholm", "SE", :sv, "SEK", "marknadsplats"),
      Entry.new("hlsinki.fi", "Helsinki", "FI", :fi, "EUR", "markkinapaikka"),
      Entry.new("brmingham.uk", "Birmingham", "GB", :"en-GB", "GBP", "marketplace"),
      Entry.new("cardff.uk", "Cardiff", "GB", :"en-GB", "GBP", "marketplace"),
      Entry.new("edinbrgh.uk", "Edinburgh", "GB", :"en-GB", "GBP", "marketplace"),
      Entry.new("glasgw.uk", "Glasgow", "GB", :"en-GB", "GBP", "marketplace"),
      Entry.new("lndon.uk", "London", "GB", :"en-GB", "GBP", "marketplace"),
      Entry.new("lverpool.uk", "Liverpool", "GB", :"en-GB", "GBP", "marketplace"),
      Entry.new("mnchester.uk", "Manchester", "GB", :"en-GB", "GBP", "marketplace"),
      Entry.new("amstrdam.nl", "Amsterdam", "NL", :nl, "EUR", "marktplaats"),
      Entry.new("rottrdam.nl", "Rotterdam", "NL", :nl, "EUR", "marktplaats"),
      Entry.new("utrcht.nl", "Utrecht", "NL", :nl, "EUR", "marktplaats"),
      Entry.new("brssels.be", "Brussels", "BE", :"fr-BE", "EUR", "marche"),
      Entry.new("zrich.ch", "Zürich", "CH", :"de-CH", "CHF", "marktplatz"),
      Entry.new("lchtenstein.li", "Liechtenstein", "LI", :"de-LI", "CHF", "marktplatz"),
      Entry.new("frankfrt.de", "Frankfurt", "DE", :de, "EUR", "marktplatz"),
      Entry.new("brdeaux.fr", "Bordeaux", "FR", :fr, "EUR", "marche"),
      Entry.new("mrseille.fr", "Marseille", "FR", :fr, "EUR", "marche"),
      Entry.new("mlan.it", "Milan", "IT", :it, "EUR", "mercato"),
      Entry.new("lisbon.pt", "Lisbon", "PT", :pt, "EUR", "mercado"),
      Entry.new("wrsawa.pl", "Warszawa", "PL", :pl, "PLN", "marktplatz"),
      Entry.new("gdnsk.pl", "Gdańsk", "PL", :pl, "PLN", "marktplatz"),
      Entry.new("austn.us", "Austin", "US", :"en-US", "USD", "marketplace"),
      Entry.new("chcago.us", "Chicago", "US", :"en-US", "USD", "marketplace"),
      Entry.new("denvr.us", "Denver", "US", :"en-US", "USD", "marketplace"),
      Entry.new("dllas.us", "Dallas", "US", :"en-US", "USD", "marketplace"),
      Entry.new("dnver.us", "Denver", "US", :"en-US", "USD", "marketplace"),
      Entry.new("dtroit.us", "Detroit", "US", :"en-US", "USD", "marketplace"),
      Entry.new("houstn.us", "Houston", "US", :"en-US", "USD", "marketplace"),
      Entry.new("lsangeles.com", "Los Angeles", "US", :"en-US", "USD", "marketplace"),
      Entry.new("mnnesota.com", "Minneapolis / Minnesota", "US", :"en-US", "USD", "marketplace"),
      Entry.new("newyrk.us", "New York", "US", :"en-US", "USD", "marketplace"),
      Entry.new("prtland.com", "Portland", "US", :"en-US", "USD", "marketplace"),
      Entry.new("wshingtondc.com", "Washington DC", "US", :"en-US", "USD", "marketplace")
    ].freeze

    ENTRIES_BY_DOMAIN = ENTRIES.to_h { |entry| [entry.domain, entry] }.freeze

    def self.resolve(host)
      normalized_host = normalize_host(host)
      normalized_host = "brgen.no" if LOCAL_HOSTS.include?(normalized_host)

      entry = entry_for(normalized_host)
      city_record = resolve_city_record(entry)
      subdomain = subdomain_for(normalized_host, entry.domain)

      Result.new(entry, city_record, subapp_for(subdomain, entry), normalized_host)
    end

    def self.normalize_host(host)
      host.to_s.downcase.split(":", 2).first.to_s.delete_suffix(".")
    end

    def self.entry_for(host)
      ENTRIES_BY_DOMAIN.values.find { |entry| host == entry.domain || host.end_with?(".#{entry.domain}") } ||
        raise(UnknownHost, host)
    end

    def self.resolve_city_record(entry)
      return unless defined?(City)

      connection = ActiveRecord::Base.connection
      return unless connection.table_exists?(:cities)

      City.find_by(domain: entry.domain)
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def self.subdomain_for(host, domain)
      return nil if host == domain

      host.delete_suffix(".#{domain}")
    end

    def self.subapp_for(subdomain, entry)
      return nil if subdomain.nil?
      return :marketplace if subdomain == entry.marketplace_subdomain

      SUBAPP_ALIASES.fetch(subdomain) { raise UnknownSubdomain, subdomain }
    end
  end
end
