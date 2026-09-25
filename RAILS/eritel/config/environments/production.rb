# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.require_master_key = false
  config.force_ssl = false
  config.active_job.queue_adapter = :solid_queue
  config.action_mailer.perform_caching = false
end
