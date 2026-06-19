# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require File.expand_path("../../../shared/config/environments/production_baseline.rb", __dir__)

Rails.application.configure do
  apply_production_baseline(config,
    hosts: ["brgen.no", /.*\.brgen\.no\z/],
    mailer_host: "brgen.no",
    secret_key_base: true,
    vapid_note: "AN106: VAPID keys in /etc/master.env when enabling push")

  config.logger = Logger.new(STDOUT)
end