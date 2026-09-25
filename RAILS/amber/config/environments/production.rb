# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require File.expand_path("../../../shared/config/environments/production_baseline.rb", __dir__)

Rails.application.configure do
  apply_production_baseline(config,
    # amberapp.art is amber's one name, so it is the only host accepted here and
    # the only one relayd routes to amber.
    hosts: [ "amberapp.art", "www.amberapp.art" ],
    mailer_host: "amberapp.art",
    vapid_note: "AN106: VAPID keys in /etc/master.env when enabling push")
end
