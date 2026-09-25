# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Eritel
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "Europe/Oslo"
    config.i18n.default_locale = :en
    config.i18n.available_locales = %i[en nb]
    config.i18n.fallbacks = true

    config.generators.system_tests = nil

    config.x.registry_provider = ENV.fetch("ERITEL_REGISTRY_PROVIDER", "simulator")
    config.x.registry_endpoint = ENV["ERITEL_REGISTRY_ENDPOINT"]
  end
end
