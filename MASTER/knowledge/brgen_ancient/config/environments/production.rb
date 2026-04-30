Brgen::Application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # -------------------------------------------------

  config.serve_static_files = false

  # -------------------------------------------------

  config.assets.js_compressor = :uglifier
  config.assets.css_compressor = :sass
  config.assets.compile = false
  config.assets.digest = true
  config.assets.initialize_on_precompile = true

  # -------------------------------------------------

  config.log_level = :info
  config.log_formatter = ::Logger::Formatter.new

  # -------------------------------------------------

  config.i18n.fallbacks = true

  # -------------------------------------------------

  config.active_support.deprecation = :notify

  # -------------------------------------------------

  # SEO: HTTPS now used as a ranking signal

  # https://goo.gl/adr7BG

  # config.force_ssl = true

  # -------------------------------------------------

  # OpenSMTPD

  config.action_mailer.delivery_method = :sendmail
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = { host: "brgen.no" }

  # -------------------------------------------------

  # OmniAuth Facebook

  # ENV["FACEBOOK_APP_ID"] = Rails.application.secrets.facebook_key.to_s
  ENV["FACEBOOK_APP_ID"] = "472035689483297"
  # ENV["FACEBOOK_SECRET"] = Rails.application.secrets.facebook_secret_key.to_s
  ENV["FACEBOOK_SECRET"] = "9eca58d4cdb2b6fb3d3876ac0eae91c6"

  # -------------------------------------------------

  config.middleware.use Rack::Attack

  # -------------------------------------------------

  config.middleware.use "HtmlMinifier"
end

