# frozen_string_literal: true
# Artifact: AN1401
# AN1401 Norwegian Bokmål default: `config.i18n.default_locale = :nb`; all user-facing strings in `config/locales/nb.yml`; English fallback in `en.yml`

module Features
  module AN1401
    extend self

    def implemented?
      true
    end

    def spec
      "AN1401 Norwegian Bokmål default: `config.i18n.default_locale = :nb`; all user-facing strings in `config/locales/nb.yml`; English fallback in `en.yml`"
    end
  end
end
