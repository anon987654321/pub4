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
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Europe/Oslo"
    config.i18n.default_locale = :nb
    config.i18n.available_locales = %i[nb en]
    config.i18n.fallbacks = { nb: :en }
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # The shared icon sprite is rendered by the layout; icons resolve via
    # <use> against it. One config value, read by Shared::UiHelper#icon_sprite?
    # and the layout, so both agree (brgen's arrangement, adopted 2026-08-21).
    config.x.icon_sprite = true

    # ports_fts and its three sync triggers exist only as raw SQL in a
    # migration, and schema.rb cannot carry a trigger. So every schema load —
    # bin/ci's db:test:prepare, each parallel test worker, a fresh db:prepare —
    # reruns that idempotent migration, and search has its index wherever the
    # schema does.
    initializer "bsdports.ports_fts_on_schema_load" do
      ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(Module.new do
        def load_schema(...)
          super
          # The cable, cache and queue databases load schemas too, with no ports.
          return unless migration_connection.data_source_exists?("ports")

          require Rails.root.join("db/migrate/20260914120000_create_ports_fts_triggers.rb").to_s
          ActiveRecord::Migration.suppress_messages { CreatePortsFtsTriggers.new.up }
        end
      end)
    end
  end
end
