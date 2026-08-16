# frozen_string_literal: true

require "faker"

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
      "lisbon.pt" => %w[lisbon portugal]
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
      "LI" => %w[lokal news]
    }.freeze

    # Faker locale ids, keyed to the same country codes as COMMUNITY_SLUGS, so
    # seeded users get names that actually sound like they're from the city's
    # country instead of generic Faker::Name defaults.
    #
    # These are Faker's own locale ids (the filenames in faker/lib/locales),
    # which are mostly region-tagged: Norwegian data lives in nb-NO.yml, not
    # nb.yml. An earlier version of this table listed bare tags ("nb", "de")
    # to stay inside config.i18n.available_locales, on the theory that a
    # region tag would raise I18n::InvalidLocale. It does raise — but a bare
    # "nb" doesn't fail loudly, it silently resolves to no Norwegian data at
    # all and hands back English: Faker::Config.locale = "nb" then
    # Faker::Name.first_name returned "Jerrell", and Faker::Address.city
    # "Gailborough". So the whole mechanism was a no-op and every city seeded
    # English-sounding people regardless of country.
    #
    # with_faker_locale widens I18n.available_locales for the duration of the
    # block instead, which is what makes the region tags usable. Seeding is
    # also the only caller, so the widening never outlives a seed run.
    LOCALE_BY_COUNTRY = {
      "NO" => "nb-NO",
      "SE" => "sv",
      "DK" => "da-DK",
      "FI" => "fi-FI",
      # Faker ships no Icelandic locale; Norwegian is the nearest Nordic
      # naming stock and reads far less wrong than English for Reykjavík.
      "IS" => "nb-NO",
      "US" => "en-US",
      "GB" => "en-GB",
      "NL" => "nl",
      "DE" => "de",
      "FR" => "fr",
      "BE" => "fr",
      "CH" => "de-CH",
      "LI" => "de-CH",
      "IT" => "it",
      "PT" => "pt",
      "PL" => "pl"
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

    # Run a block with Faker speaking the city's language.
    #
    # Faker resolves its data through the host app's I18n backend, so a locale
    # the app doesn't declare raises I18n::InvalidLocale — and the app only
    # declares the five it ships UI copy for. Both the allowlist and
    # Faker::Config.locale are process-global, so both are restored on the way
    # out; a seed_all! run over many cities would otherwise leak the last
    # city's locale into everything after it.
    def with_faker_locale(country_code)
      locale = locale_for(country_code)
      previous_available = I18n.available_locales
      previous_locale = Faker::Config.locale

      I18n.available_locales = (previous_available + [ locale.to_sym ]).uniq
      Faker::Config.locale = locale
      yield
    ensure
      Faker::Config.locale = previous_locale
      I18n.available_locales = previous_available
    end
  end
end
