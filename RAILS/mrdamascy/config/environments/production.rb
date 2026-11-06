# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings.
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching by default.
  config.action_controller.perform_caching = true

  # Serve static files and give everything outside the fingerprinted assets a
  # short lifetime — the manifest and service worker must be able to change.
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.hour.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Cache in its own SQLite database. Jobs run in-process (:async): the app
  # enqueues none of its own, and on vm23 a Solid Queue supervisor, worker and
  # dispatcher would cost more resident memory than the app itself. Go back to
  # :solid_queue, with connects_to the queue database and an rc.d worker, the
  # day it gains real background work.
  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :async

  # relayd terminates TLS on vm23 and serves only port 443, so every request is
  # https already. assume_ssl makes Rails believe it; force_ssl would add a
  # second HSTS header beside relayd's and redirect its plain-http /up probe.
  config.assume_ssl = true

  # The demo host. /up and /health answer any Host, so rc.d and relayd can probe
  # the loopback without one.
  config.hosts = [ "mrd.brgen.no" ]
  config.host_authorization = { exclude: ->(request) { %w[/up /health].include?(request.path) } }

  # Log to STDOUT by default, tagged with the request id so interleaved
  # requests stay readable.
  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info").to_sym
  config.silence_healthcheck_path = "/up"

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only dump the attributes of interest for inspection.
  config.active_record.attributes_for_inspect = [ :id ]

  # Mail: links generated from one host, delivery errors are loud.
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = { host: ENV.fetch("MRDAMASCY_HOST", "mrd.brgen.no"), protocol: "https" }

  # No blanket `config.i18n.fallbacks = true` here: environment config loads
  # after application.rb, and a blanket true would silently overwrite this
  # app's own { nb: :en } chain.

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the default locale when a translation cannot be found).
  # (Set once in application.rb — do not restate.)

  # Report deprecations related to Rails app code — off in production.
  config.active_support.report_deprecations = false
end
