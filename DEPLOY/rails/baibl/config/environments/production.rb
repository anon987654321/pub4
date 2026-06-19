# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require File.expand_path("../../../shared/config/environments/production_baseline.rb", __dir__)

Rails.application.configure do
  apply_production_baseline(config,
    hosts: ["baibl.no", "www.baibl.no", "baibl.brgen.no"],
    mailer_host: "baibl.no")
end