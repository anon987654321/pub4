# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

require File.expand_path("../../lib/pub/catalog.rb", __dir__)

module Bplan
  class Application < Rails::Application
    config.load_defaults 8.1
    config.time_zone = "Europe/Oslo"
    config.i18n.default_locale = :nb
    config.i18n.available_locales = %i[nb en]
    config.i18n.fallbacks = { nb: :en }
    config.generators.system_tests = nil
  end
end