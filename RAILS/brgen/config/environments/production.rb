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
  # :warn, not the :info default. rc.d captures stdout into syslog, which fans
  # it into BOTH /var/log/messages and /var/log/daemon, so every request line is
  # written twice. At :info that is each request, each fragment-cache read and
  # each enqueued job — measured 2026-08-08 as 1.9G in each of those two files,
  # with /var at 106% and the CI test step dying mid-deploy because it could not
  # write. Rotation is the real guard and is now restored (OPENBSD/etc/
  # newsyslog.conf, which had lost every base rule), but a production app has no
  # business narrating cache reads to the system log twice over.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "warn").to_sym
end
