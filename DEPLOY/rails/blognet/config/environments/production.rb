# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require File.expand_path("../../../shared/config/environments/production_baseline.rb", __dir__)

Rails.application.configure do
  apply_production_baseline(config,
    hosts: [ "blognet.no", "www.blognet.no", "blognet.brgen.no" ],
    mailer_host: "blognet.no")
end
