# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require File.expand_path("../../../shared/config/environments/production_baseline.rb", __dir__)

Rails.application.configure do
  apply_production_baseline(config,
    # amber.fashion is amber's own name, registered 2026-09-16, and the only one
    # it answers on: amber.brgen.no ceased to exist the same day, so nothing here
    # accepts it and the relay has no match for it either.
    hosts: [ "amber.fashion", "www.amber.fashion" ],
    mailer_host: "amber.fashion",
    vapid_note: "AN106: VAPID keys in /etc/master.env when enabling push")
end
