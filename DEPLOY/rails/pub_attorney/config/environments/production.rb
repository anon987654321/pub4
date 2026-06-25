# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require File.expand_path("../../../shared/config/environments/production_baseline.rb", __dir__)

Rails.application.configure do
  apply_production_baseline(config,
    hosts: [ "pub.attorney" ],
    mailer_host: "pub.attorney",
    vapid_note: "AN106: VAPID keys in /etc/master.env when enabling push")
end
