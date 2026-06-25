# frozen_string_literal: true

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
# require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../app/middleware/auth_tier"

class ServiceWorkerNoCache
  def initialize(app) = @app = app

  def call(env)
    status, headers, body = @app.call(env)
    headers["Cache-Control"] = "no-cache, no-store, must-revalidate" if env["PATH_INFO"] == "/sw.js"
    [status, headers, body]
  end
end

module Web
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks master])
    # Face sources live in public/; never treat digest output (public/assets/) as input.
    config.assets.paths << Rails.root.join("public")
    config.assets.excluded_paths << Rails.root.join("public", "assets")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.middleware.insert_before ActionDispatch::Static, ServiceWorkerNoCache

    config.middleware.use(
      AuthTier,
      config_path: Rails.root.join("..", ".master", "config.yml").to_s
    )
  end
end
