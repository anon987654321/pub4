# frozen_string_literal: true

module Brgen
  module LocaleBridge
    NORDIC = %i[nb is da sv fi].freeze
    GERMANIC = %i[de de-CH de-LI nl].freeze
    ROMANCE = %i[fr fr-BE it pt pl].freeze
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
      }
    end
  end
end
