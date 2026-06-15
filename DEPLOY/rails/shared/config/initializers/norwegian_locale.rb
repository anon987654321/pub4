# frozen_string_literal: true
# AN1401-AN1405: Norwegian locale defaults

Rails.application.configure do
  config.i18n.default_locale = :nb
  config.i18n.fallbacks = [:en]
  config.time_zone = "Europe/Oslo"
end