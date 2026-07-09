# frozen_string_literal: true

# Shared OpenBSD/relayd production baseline — apps call apply_production_baseline with host overrides.
def apply_production_baseline(config, hosts:, mailer_host: nil, vapid_note: nil, secret_key_base: false)
  mailer_host ||= Array(hosts).first

  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") if secret_key_base

  config.yjit = true if config.respond_to?(:yjit=)

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }
  config.active_storage.service = :local

  config.assume_ssl = true

  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"

  if vapid_note
    warn vapid_note if defined?(Rails) && Rails.env.production?
  end

  config.active_support.report_deprecations = false
  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = { host: mailer_host, protocol: "https" }
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = { address: "127.0.0.1", port: 25 }

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]

  config.hosts = Array(hosts)
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
