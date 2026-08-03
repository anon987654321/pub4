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

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
require_relative "../lib/brgen/locale_bridge"

module App
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
    # Draw icons from a single <symbol> sprite instead of inlining the paths at
    # every call site. On for brgen because its feed renders 147 icons from 22
    # shapes and the sprite takes ~30KB off the homepage; off elsewhere, where a
    # page draws one or two icons and the 8.2KB sprite would cost more than it
    # saves. Read by both Shared::UiHelper#icon and the layout, so the two cannot
    # disagree about which form is on. See shared/app/views/shared/_icon_sprite.
    config.x.icon_sprite = true

    config.time_zone = "Europe/Oslo"
    config.i18n.default_locale = :nb
    config.i18n.available_locales = %i[nb en nl de fr]
    config.i18n.fallbacks = Brgen::LocaleBridge.fallbacks_map
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
