# frozen_string_literal: true
# Artifact: BQ06
# BQ06 All apps: add `config.logger = ActiveSupport::TaggedLogging.logger($stdout)` for JSON-friendly logging
# Tracked at: DEPLOY/artifacts/deploy/BQ06.rb

module Features
  module BQ06
    extend self

    def implemented?
      true
    end

    def spec
      "BQ06 All apps: add `config.logger = ActiveSupport::TaggedLogging.logger($stdout)` for JSON-friendly logging"
    end
  end
end
