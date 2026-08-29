# frozen_string_literal: true

module Brgen
  # Entry.locale is the language of the city. This decides what I18n.locale
  # becomes, which is a different question: it may only name a locale brgen
  # actually ships a translation for.
  #
  # Two locales ship — nb and en — so this maps to two.
  #
  # de.yml, fr.yml and nl.yml existed and held five keys each: hello, app.name,
  # feed.title, nav.sign_in, nav.new_post, against en.yml's 1579. Eleven city
  # domains routed to them, so those pages rendered five translated words and
  # 1574 English ones — which reads worse than a page that is in English,
  # because a reader cannot tell whether the rest is missing or the product is.
  #
  # Two were served the wrong language outright. mlan.it and lisbon.pt resolved
  # to :fr under a rule that mapped Italian and Portuguese to "the nearest
  # available Romance locale"; French chrome on an Italian city is not nearer
  # than English. That is the same mistake the Polish note below records, and it
  # survived the fix because the rule was narrowed rather than dropped.
  #
  # The stubs are deleted rather than kept unrouted: a locale file nothing loads
  # is the inert-config shape this tree keeps finding. Filling them is a
  # translation budget and a product decision — TODO.md carries it — and
  # until then these cities get one language, consistently.
  module LocaleBridge
    NORDIC = %i[nb is da sv fi].freeze

    module_function

    def resolve(locale)
      sym = locale.to_sym
      return sym if I18n.available_locales.include?(sym)
      return :nb if NORDIC.include?(sym)

      :en
    end

    # Nordic languages fall to nb before en: a Danish or Swedish reader is far
    # better served by Norwegian than by English, and Icelandic has no Faker
    # locale either (see CityContent::LOCALE_BY_COUNTRY).
    #
    # en is terminal, and nothing falls back to it from below. It used to: the
    # map read `en: %i[nb]`, so a key missing from en.yml would have rendered
    # one Norwegian sentence inside an English paragraph, which reads as a bug
    # rather than as a gap. It never fired — RAILS/test/locale_contract_test.rb
    # asserts en and nb declare the same keys, and they do, all 1579 of them.
    # A fallback reachable only by breaking a contract test, and wrong when it
    # is reached, is not a safety net.
    def fallbacks_map
      nordic = NORDIC.reject { |code| code == :nb }.to_h { |code| [ code, %i[nb en] ] }

      { nb: %i[en], "en-US": %i[en], "en-GB": %i[en] }.merge(nordic)
    end
  end
end
