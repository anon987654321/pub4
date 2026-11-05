# frozen_string_literal: true

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MrDamascy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # One Bergen kitchen (Danmarksplass): orders, ETAs and stamps all live on
    # Norwegian local time.
    config.time_zone = "Europe/Oslo"
    config.i18n.default_locale = :nb
    config.i18n.available_locales = %i[nb en]
    config.i18n.fallbacks = { nb: :en }

    # Tips after delivery. Off unless MRDAMASCY_TIPS=1: both payment lanes have
    # captured the order by the time it is delivered and neither can charge
    # again, so a tip would be a promise the app cannot collect. With the flag
    # on, a tip is recorded and shown as not paid in the app (Order#add_tip!).
    config.x.tips = ENV.fetch("MRDAMASCY_TIPS", "0") == "1"

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
