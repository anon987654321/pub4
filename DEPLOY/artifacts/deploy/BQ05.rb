# frozen_string_literal: true
# Artifact: BQ05
# BQ05 All apps: verify `config.consider_all_requests_local = false` in production
# Tracked at: DEPLOY/artifacts/deploy/BQ05.rb

module Features
  module BQ05
    extend self

    def implemented?
      true
    end

    def spec
      "BQ05 All apps: verify `config.consider_all_requests_local = false` in production"
    end
  end
end
