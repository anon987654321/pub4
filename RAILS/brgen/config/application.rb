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
    # Two, because two ship. de/fr/nl held five keys each against en's 1579 and
    # were deleted 2026-08-25; see Brgen::LocaleBridge for why a stub locale is
    # worse than none.
    config.i18n.available_locales = %i[nb en]
    config.i18n.fallbacks = Brgen::LocaleBridge.fallbacks_map
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # `bin/rails test` must mean what CI means.
    #
    # Rails globs test/**/*_test.rb from the app root, which does not reach the
    # mountable verticals under engines/*/test. shared/config/ci.rb sets
    # DEFAULT_TEST/DEFAULT_TEST_EXCLUDE so the VPS runs them; nothing set it
    # locally, so the two commands disagreed about what "the suite" is and the
    # local one was the weaker.
    #
    # That gap has now bitten twice. ci.rb's own comment records four engine
    # tests rotting into NameErrors on a stale route helper while CI stayed
    # green; on 2026-08-10 a validation-i18n change broke two takeaway engine
    # tests and three sessions reported "brgen green" from the narrow command
    # before the VPS gate caught it — 349 runs locally against CI's 381.
    #
    # Set here rather than documented again, because a third warning comment
    # would have been the third thing nobody read. ||= so an explicit
    # DEFAULT_TEST on the command line still wins, and so ci.rb's own values
    # pass through unchanged.
    if Rails.env.test? || ENV["RAILS_ENV"] == "test"
      ENV["DEFAULT_TEST"] ||= "{test,engines/*/test}/**/*_test.rb"
      ENV["DEFAULT_TEST_EXCLUDE"] ||= "{test,engines/*/test}/{system,dummy,fixtures}/**/*_test.rb"
    end
  end
end
