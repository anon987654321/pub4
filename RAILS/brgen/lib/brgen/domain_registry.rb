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
      "messenger" => :messenger,
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

    TV_SUBDOMAINS = %w[tv].freeze
    DATING_SUBDOMAINS = %w[dating].freeze
    # `playlist` in every city, including the Norwegian ones. `spilleliste` was
    # here as a second Norwegian-language host for the same engine, and it was
    # the odd one out: marketplace is translated per country because the word is
    # part of the brand in each market (markedsplass, marknadsplats, marktplatz,
    # mercato), while dating, tv, takeaway, maps and messenger are the same word
    # everywhere and were never translated. Playlist is in that second group.
    # It also never resolved — spilleliste.brgen.no and spilleliste.oshlo.no were
    # both NXDOMAIN, so every gate and flow pointing at it was measuring nothing.
    PLAYLIST_SUBDOMAINS = %w[playlist].freeze
    TAKEAWAY_SUBDOMAINS = %w[takeaway].freeze
    MARKETPLACE_SUBDOMAINS = SUBAPP_ALIASES.select { |_subdomain, subapp| subapp == :marketplace }.keys.freeze
    MAPS_SUBDOMAINS = %w[maps].freeze
    MESSENGER_SUBDOMAINS = %w[messenger].freeze

    LOCAL_HOSTS = [ "127.0.0.1", "localhost" ].freeze

    # Entry.locale is the language of the city, not a promise that we ship a
    # YAML file for it. LocaleBridge.resolve is what I18n.locale becomes —
    # da/sv/fi/is → nb, and everything else → en. Do not add a thin locale
    # file that is a copy of another language; that is a claim.
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
      Entry.new("dtroit.us", "Detroit", "US", :"en-US", "USD", "marketplace"),
      Entry.new("houstn.us", "Houston", "US", :"en-US", "USD", "marketplace"),
      Entry.new("lsangeles.com", "Los Angeles", "US", :"en-US", "USD", "marketplace"),
      Entry.new("mnnesota.com", "Minneapolis / Minnesota", "US", :"en-US", "USD", "marketplace"),
      Entry.new("newyrk.us", "New York", "US", :"en-US", "USD", "marketplace"),
      Entry.new("prtland.com", "Portland", "US", :"en-US", "USD", "marketplace"),
      Entry.new("wshingtondc.com", "Washington DC", "US", :"en-US", "USD", "marketplace")
    ].freeze

    ENTRIES_BY_DOMAIN = ENTRIES.index_by(&:domain).freeze

    # The city apexes that actually serve this app. Every other ENTRIES row is a
    # domain we intend to run and have wired into OPERATOR.sh#ALL_DOMAINS, but
    # relayd only answers for an apex whose certificate exists on disk — see
    # TODO.md "City vanity TLS". Linking the rest puts dead links in
    # front of every visitor, so nothing user-facing may iterate ENTRIES.
    #
    # Ground truth is `grep keypair /etc/relayd.conf` on vm23, and domain_alignment
    # now asserts this list equals (ENTRIES ∩ those keypairs) so it cannot drift
    # silently in either direction.
    #
    # Seven, as of 2026-08-12, up from two. The five that joined were not five new
    # certificates: acme-client had been issuing and renewing for stvanger.no,
    # trndheim.no, cardff.uk, edinbrgh.uk and frankfrt.de all along, and all five
    # resolved to 46.23.89.226. They were missing one `tls keypair` line each, so
    # they completed the TCP connection on 443 and then refused the handshake —
    # which to a visitor is worse than NXDOMAIN, because a browser reports it as a
    # security failure rather than a domain that does not exist.
    #
    # The rest of ENTRIES: 33 are NXDOMAIN at their registrar and need money, not
    # config. amstrdam.nl and dnver.us have left us — amstrdam.nl is on Cloudflare
    # and 301s to afvinklijst.nl, dnver.us has expired. denvr.us, wshingtondc.com
    # and foball.no are still registered to us at Domeneshop and delegated to
    # Domeneshop's parking nameservers rather than ns.brgen.no; those three come
    # back with a delegation change in the panel and no purchase.
    #
    # This is a separate constant rather than a seventh field on Entry because
    # domain_alignment parses these lines with a six-argument regex. A seventh
    # field makes that scan return nothing, and the gate then compares two empty
    # sets and passes having measured nothing.
    LIVE_DOMAINS = %w[
      brgen.no oshlo.no stvanger.no trndheim.no cardff.uk edinbrgh.uk frankfrt.de
    ].freeze

    # fetch, not [], so a domain deleted from ENTRIES takes the page down here
    # rather than silently shrinking the city network to whatever still matches.
    def self.live_entries
      LIVE_DOMAINS.map { |domain| ENTRIES_BY_DOMAIN.fetch(domain) }
    end

    def self.production_hosts
      ENTRIES.flat_map { |entry| [ entry.domain, /.*\.#{Regexp.escape(entry.domain)}\z/ ] }.uniq
    end

    def self.resolve(host)
      normalized_host = normalize_host(host)
      normalized_host = "brgen.no" if LOCAL_HOSTS.include?(normalized_host)

      entry = entry_for(normalized_host)
      city_record = resolve_city_record(entry)
      subdomain = subdomain_for(normalized_host, entry.domain)

      Result.new(entry, city_record, subapp_for(subdomain, entry), normalized_host)
    end

    def self.normalize_host(host)
      host.to_s.downcase.split(":", 2).first.to_s.delete_suffix(".").sub(/\Awww\./, "")
    end

    def self.entry_for(host)
      ENTRIES_BY_DOMAIN.values.find { |entry| host == entry.domain || host.end_with?(".#{entry.domain}") } ||
        raise(UnknownHost, host)
    end

    def self.resolve_city_record(entry)
      return unless defined?(City)
      return unless cities_table?

      City.find_by(domain: entry.domain)
    # cities_table? is checked on the way in. A StatementInvalid past that point
    # is a schema fault, and swallowing it makes every city resolve to no
    # record — which reads as an unconfigured city rather than a broken one.
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn("domain_registry city lookup: #{e.class}: #{e.message}")
      nil
    end

    # Memoised because a table cannot appear or vanish inside a running process,
    # and this ran a schema probe on every request alongside the lookup it
    # guards. The boot-order case it exists for — the registry resolving before
    # migrations have run — only needs answering once.
    def self.cities_table?
      return @cities_table if defined?(@cities_table)

      @cities_table = ActiveRecord::Base.connection.table_exists?(:cities)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      @cities_table = false
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

    def self.subreddits_for(domain)
      Brgen::CityContent.subreddits_for(domain)
    end
  end
end
