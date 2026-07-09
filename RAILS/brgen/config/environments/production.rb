# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require File.expand_path("../../../shared/config/environments/production_baseline.rb", __dir__)
require File.expand_path("../../lib/brgen/domain_registry", __dir__)

Rails.application.configure do
  apply_production_baseline(config,
                            hosts: Brgen::DomainRegistry.production_hosts, # brgen.no + city apex/subdomains
                            mailer_host: "brgen.no",
                            secret_key_base: true,
                            vapid_note: "AN106: VAPID keys in /etc/master.env when enabling push")

  config.logger = Logger.new($stdout)
end
