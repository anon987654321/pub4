# frozen_string_literal: true

module Brgen
  module CityContent
    SUBREDDITS_BY_DOMAIN = {
      "brgen.no" => %w[bergen norge],
      "longyearbyn.no" => %w[longyearbyen norge],
      "oshlo.no" => %w[oslo norge],
      "stvanger.no" => %w[stavanger norge],
      "trmso.no" => %w[tromso norge],
      "trndheim.no" => %w[trondheim norge],
      "reykjavk.is" => %w[reykjavik iceland],
      "kbenhvn.dk" => %w[copenhagen denmark],
      "gtebrg.se" => %w[gothenburg sweden],
      "mlmoe.se" => %w[malmo sweden],
      "stholm.se" => %w[stockholm sweden],
      "hlsinki.fi" => %w[helsinki finland],
      "lndon.uk" => %w[london unitedkingdom],
      "amstrdam.nl" => %w[amsterdam thenetherlands],
      "rottrdam.nl" => %w[rotterdam thenetherlands],
      "lsangeles.com" => %w[LosAngeles california],
      "newyrk.us" => %w[nyc AskNYC],
      "prtland.com" => %w[portland oregon],
      "chcago.us" => %w[chicago illinois],
      "frankfrt.de" => %w[frankfurt germany],
      "mrseille.fr" => %w[marseille france],
      "mlan.it" => %w[milan italy],
      "lisbon.pt" => %w[lisbon portugal],
    }.freeze

    COMMUNITY_SLUGS = {
      "NO" => %w[bergen norge kultur mat musikk],
      "US" => %w[local news food music culture],
      "NL" => %w[amsterdam nederland nieuws eten],
      "GB" => %w[local news food music],
      "DE" => %w[lokal nachrichten essen],
      "FR" => %w[local actualites nourriture],
      "SE" => %w[lokalt nyheter mat],
      "DK" => %w[lokalt nyheder mad],
      "FI" => %w[paikallinen uutiset],
      "IS" => %w[local news],
      "IT" => %w[locale notizie cibo],
      "PT" => %w[local noticias comida],
      "PL" => %w[lokalne wiadomosci],
      "BE" => %w[local actualites],
      "CH" => %w[lokal news],
      "LI" => %w[lokal news],
    }.freeze

    # Faker locales, keyed to the same country codes as COMMUNITY_SLUGS, so
    # seeded users get names that actually sound like they're from the city's
    # country instead of generic Faker::Name defaults.
    #
    # Restricted to config.i18n.available_locales (application.rb: nb, en,
    # nl, de, fr) -- Faker::Config.locale ultimately goes through the app's
    # own I18n backend when Faker runs inside a booted Rails process, which
    # raises I18n::InvalidLocale for anything outside that allowlist (region
    # variants like "nb-NO"/"en-US" included, since available_locales lists
    # bare :nb/:en, not region tags). Faker itself supports many more locale
    # files standalone, but this app doesn't declare them as available, and
    # broadening available_locales is a real app-behavior change this seed-
    # data fix has no business making. Countries outside this set fall back
    # to "en", same as community_slugs_for falls back to COMMUNITY_SLUGS["US"].
    LOCALE_BY_COUNTRY = {
      "NO" => "nb",
      "US" => "en",
      "NL" => "nl",
      "GB" => "en",
      "DE" => "de",
      "FR" => "fr",
      "BE" => "fr",
      "CH" => "de",
      "LI" => "de",
      "IS" => "nb",
    }.freeze

    module_function

    def subreddits_for(domain)
      SUBREDDITS_BY_DOMAIN.fetch(domain) { [ domain.to_s.split(".").first ] }
    end

    def community_slugs_for(country_code)
      COMMUNITY_SLUGS.fetch(country_code.to_s.upcase, COMMUNITY_SLUGS["US"])
    end

    def locale_for(country_code)
      LOCALE_BY_COUNTRY.fetch(country_code.to_s.upcase, LOCALE_BY_COUNTRY["US"])
    end
  end
end
