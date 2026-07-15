# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }
  config.active_support.report_deprecations = false
  config.assume_ssl = true
  config.force_ssl = false
  config.silence_healthcheck_path = "/up"
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") if ENV["SECRET_KEY_BASE"].present?

  config.hosts = [
    "bplan.pub.healthcare",
    "127.0.0.1",
    "localhost",
  ]
  config.host_authorization = {
    exclude: ->(request) { request.path == "/up" },
  }
end