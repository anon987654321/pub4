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

require_relative "../app/services/master_web_token"
require_relative "../app/middleware/auth_tier"
require_relative "../app/middleware/html_no_store"
require_relative "../app/middleware/security_headers"

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

    # nb is the default because ai.brgen.no is the only host relayd forwards
    # here, and it is the same Norwegian audience brgen, amber and bsdports all
    # default to nb for. ApplicationController#set_locale hands English back to a
    # browser that asks for it — the face answers whoever reaches it, and a
    # Norwegian frame around an English conversation is worse than either.
    #
    # The fallback is what makes nb safe to switch on: a key nb has not got yet
    # renders its English rather than translation_missing. It is also what makes
    # nb/en parity worth enforcing in web/test/locale_contract_test.rb, since
    # a gap is invisible at runtime by design. The RAILS contract of the same
    # name does not see this app.
    config.i18n.default_locale = :nb
    config.i18n.available_locales = %i[nb en]
    config.i18n.fallbacks = { nb: :en }

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.middleware.insert_before ActionDispatch::Static, ServiceWorkerNoCache

    config.middleware.use(
      AuthTier,
      config_path: -> { MasterWebToken.config_path },
    )
    config.middleware.insert_before Rack::ETag, SecurityHeaders
    config.middleware.insert_before Rack::ETag, HtmlNoStore
  end
end
