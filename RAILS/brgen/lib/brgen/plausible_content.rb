# frozen_string_literal: true

module Brgen
  # Content pools for the *bulk* of seed data.
  #
  # BergenDemoSeeder already carries hand-curated Bergen content (real places,
  # real neighbourhoods, Norwegian copy) but it only produces a few dozen
  # records. db/seeds.rb then generates hundreds to thousands more from raw
  # Faker, and those were the ones giving the site away: Faker::Lorem Latin in
  # a Norwegian city feed, Faker::Company.name ("Stokes-Bernier") on Bergen
  # shopfronts, Faker::Movie.title on a local TV channel, and — worst — a
  # Faker::Address.city on listings that had Bergen coordinates, so a bike for
  # sale in Bergen claimed to be in "Gailborough".
  #
  # These pools keep the volume but make each record locally plausible. They
  # are deliberately generic within Norwegian city life (no Bergen-only
  # landmarks) so the same pools read correctly for Oslo, Stavanger, Tromsø and
  # the other Norwegian domains in DomainRegistry.
  #
  # Non-Norwegian cities fall back to ENGLISH_* — worse than native copy, but
  # authoring eleven languages of body text is not something a seed file should
  # pretend to do, and English at least parses as language where Lorem did not.
  module PlausibleContent
    # Real Bergen street names, for addresses that should look like addresses.
    # Faker's nb-NO street generator invents plausible-but-fake compounds
    # ("Damroa"); a delivery address in a takeaway demo reads better real.
    BERGEN_STREETS = [
      "Torgallmenningen", "Strandgaten", "Vaskerelven", "Nygårdsgaten",
      "Kong Oscars gate", "Marken", "Håkonsgaten", "Nordnesveien",
      "Øvre Korskirkeallmenningen", "Fjøsangerveien", "Møllendalsveien",
      "Sandviksveien", "Fantoftvegen", "Ibsens gate", "Lars Hilles gate",
      "Christies gate", "Olav Kyrres gate", "Vestre Torggaten",
      "Neumanns gate", "Danmarksplass"
    ].freeze

    BERGEN_BYDELER = %w[
      Sentrum Nordnes Sandviken Kalfaret Møhlenpris Laksevåg
      Fyllingsdalen Fana Årstad Åsane Arna Ytrebygda
    ].freeze

    # --- TV ----------------------------------------------------------------

    TV_CHANNEL_NAMES = [
      "Vestland Nyheter", "Bergen Byliv", "Fjordkanalen", "Studio Nordnes",
      "Bybanen TV", "Sport Vest", "Kultur i Vest", "Marken Media",
      "Regnbyen Radio & TV", "Havn og Hav", "Ulriken Live", "Bergen Matglede",
      "Vestkanten Sport", "Nattkanalen", "Studenttv Bergen"
    ].freeze

    TV_VIDEO_TITLES = [
      "Bybanen til Åsane — hva skjer nå?", "Sesongstart på Brann Stadion",
      "Slik lager du fiskesuppe", "Regnrekord i februar",
      "Møt bakeren på Nordnes", "Turtips: Rundemanen på en time",
      "Studentlivet i Bergen", "Fisketorget en tidlig morgen",
      "Konsertsommer i Grieghallen", "Nye sykkelveier i sentrum",
      "Hva koster det å bo i Bergen?", "Vinter på Ulriken",
      "Fem kafeer verdt en omvei", "Havnen døgnet rundt",
      "Kulturnatt — høydepunkter", "Slik pusser du opp gammelt trehus"
    ].freeze

    module_function

    def store_name
      base = "#{Commerce::STORE_PREFIXES.sample} #{Commerce::STORE_KINDS.sample}"
      suffix = Commerce::STORE_SUFFIXES.sample
      suffix.empty? ? base : "#{base} #{suffix}"
    end

    # Pick the product first, and report the leaf category it belongs in, so the
    # caller can file the listing consistently instead of guessing.
    # Returns [title, leaf_category_slug].
    def listing_for(available_leaf_slugs)
      usable = available_leaf_slugs & Commerce::LISTING_TITLES.keys
      slug = (usable.presence || Commerce::LISTING_TITLES.keys).sample
      [ Commerce::LISTING_TITLES.fetch(slug).sample, slug ]
    end

    # [name, cuisine] for the nth seeded restaurant. Cycles the curated pool and
    # opens a "branch" in a bydel once past the end, which is how a real chain
    # would extend rather than inventing a new brand each time.
    def restaurant_for(index)
      name, cuisine = Commerce::RESTAURANTS_BY_CUISINE[index % Commerce::RESTAURANTS_BY_CUISINE.size]
      round = index / Commerce::RESTAURANTS_BY_CUISINE.size
      name = "#{name} #{BERGEN_BYDELER.sample}" unless round.zero?
      [ name, cuisine ]
    end

    def listing_body(bydel: BERGEN_BYDELER.sample)
      format_with(Commerce::LISTING_BODIES.sample, bydel: bydel)
    end

    def post_title(city_name, norwegian: true)
      pool = norwegian ? Prose::NORWEGIAN_POST_TITLES : Prose::ENGLISH_POST_TITLES
      format_with(pool.sample, city: city_name)
    end

    def post_body(norwegian: true)
      openers = norwegian ? Prose::NORWEGIAN_POST_OPENERS : Prose::ENGLISH_POST_OPENERS
      closers = norwegian ? Prose::NORWEGIAN_POST_CLOSERS : Prose::ENGLISH_POST_CLOSERS
      "#{openers.sample} #{closers.sample}"
    end

    def street_address
      "#{BERGEN_STREETS.sample} #{rand(1..98)}"
    end

    def dishes_for(cuisine)
      Commerce::DISHES_BY_CUISINE[cuisine] || Commerce::DISHES_BY_CUISINE["Norwegian"]
    end

    def norwegian_country?(country_code)
      country_code.to_s.upcase == "NO"
    end

    # Commerce::LISTING_TITLES is keyed by root category; seeded categories are slugged
    # "electronics-phones" etc. by db/seeds.rb.
    def root_category(slug)
      slug.to_s.split("-").first
    end

    # Only substitutes the keys a template actually uses, so a template with
    # no placeholders (most of them) passes through untouched rather than
    # raising KeyError on a stray %.
    def format_with(template, **values)
      values.reduce(template) { |acc, (key, value)| acc.gsub("%{#{key}}", value.to_s) }
    end
  end
end
