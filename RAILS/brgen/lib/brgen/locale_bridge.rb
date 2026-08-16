# frozen_string_literal: true

module Brgen
  module LocaleBridge
    NORDIC = %i[nb is da sv fi].freeze
    GERMANIC = %i[de de-CH de-LI nl].freeze
    # pl is West Slavic, not Romance — it was in this list, so wrsawa.pl
    # resolved to :fr and Warsaw was served a French interface. Polish has no
    # entry in available_locales, so it now falls through to :en like any other
    # unsupported language. it/pt stay: mapping them to the nearest available
    # Romance locale is deliberate.
    ROMANCE = %i[fr fr-BE it pt].freeze
    ENGLISH = %i[en en-US en-GB].freeze

    module_function

    def resolve(locale)
      sym = locale.to_sym
      return sym if I18n.available_locales.include?(sym)

      return :nb if NORDIC.include?(sym)
      return :en if ENGLISH.include?(sym)
      return :nl if sym == :nl
      return :de if GERMANIC.include?(sym)
      return :fr if ROMANCE.include?(sym)

      :en
    end

    def fallbacks_map
      {
        nb:    %i[en],
        en:    %i[nb],
        nl:    %i[en],
        de:    %i[en],
        fr:    %i[en],
        "en-US": %i[en],
        "en-GB": %i[en],
        is:    %i[nb en],
        da:    %i[nb en],
        sv:    %i[nb en],
        fi:    %i[nb en],
        it:    %i[en fr],
        pt:    %i[en fr],
        pl:    %i[en de],
        "de-CH": %i[de en],
        "de-LI": %i[de en],
        "fr-BE": %i[fr en]
      }
    end
  end
end
