# frozen_string_literal: true

# Shared OpenBSD/relayd production baseline — apps call apply_production_baseline with host overrides.
def apply_production_baseline(config, hosts:, mailer_host: nil, vapid_note: nil, secret_key_base: true)
  mailer_host ||= Array(hosts).first

  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") if secret_key_base && ENV["SECRET_KEY_BASE"].present?

  # vm23 is 1 GB. rc.d exports RUBY_YJIT_ENABLE=0; Rails would otherwise call
  # RubyVM::YJIT.enable at the end of boot and undo that decision.
  config.yjit = false if config.respond_to?(:yjit=)

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = true
  # Not a year on everything under public/. Propshaft serves the fingerprinted
  # assets and sets its own immutable caching on them; this header reached the
  # rest of the tree too — robots.txt, manifest.json, the service worker — and
  # those are the files whose whole job is to change. A stale service worker is
  # a client pinned to an old build for as long as the cache holds.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.hour.to_i}" }
  config.active_storage.service = :local

  # Optional global CDN for Propshaft assets (e.g. https://cdn.example.com).
  # Unset = serve from origin via public_file_server (OpenBSD/relayd). Never
  # force_ssl here — TLS terminates at relayd (see production gates).
  cdn_asset_host = ENV["CDN_ASSET_HOST"].to_s.strip
  config.asset_host = cdn_asset_host if cdn_asset_host.present?

  config.assume_ssl = true
  config.force_ssl = false

  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "warn")
  config.silence_healthcheck_path = "/up"

  if vapid_note
    warn vapid_note if defined?(Rails) && Rails.env.production?
  end

  config.active_support.report_deprecations = false
  # Compressed, because on vm23 the scarce resource is memory and the spare one
  # is CPU. brgen's production cache is 56M of mostly rendered HTML, which is
  # about as compressible as data gets, and every megabyte of it competes for a
  # page cache that had 155M to work with while swap sat at 91%. The box idles at
  # 84% on one core, so the deflate is paid out of what is already spare.
  #
  # 1KB threshold: below that the header costs more than the saving, and cache
  # entries that small are counters rather than fragments.
  config.cache_store = :solid_cache_store, { compress: true, compress_threshold: 1.kilobyte }
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  apply_mail_and_url_baseline(config, mailer_host)

  # No `config.i18n.fallbacks = true` here. Environment config loads after
  # application.rb, so a blanket `true` set here silently overwrote every app's
  # own chain: brgen's Brgen::LocaleBridge.fallbacks_map (17 locales, Nordic to
  # nb, Romance to fr, de-CH to de to en) and amber's and bsdports' { nb: :en }.
  # All three apps set their own; none of them got it in production.
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  config.hosts = Array(hosts)
  config.host_authorization = {
    exclude: ->(request) { %w[/up /health].include?(request.path) },
  }
end

# Extracted from apply_production_baseline rather than inlined: the method-length
# ratchet asks for a split before a bigger number, and mail delivery plus URL
# generation is one subject.
def apply_mail_and_url_baseline(config, mailer_host)
  # One value, two consumers. action_mailer.default_url_options only reaches
  # ActionMailer; anything generating a URL through Rails.application.routes —
  # an isolated engine's main_app proxy, a job, a runner — reads
  # routes.default_url_options, which was unset in every environment. The
  # passwordless mailer read the second one, got no host, and shipped a
  # relative path. Derived from one local so the two cannot drift.
  url_options = { host: mailer_host, protocol: "https" }

  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = url_options
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = { address: "127.0.0.1", port: 25 }
  config.after_initialize { Rails.application.routes.default_url_options = url_options }
end
