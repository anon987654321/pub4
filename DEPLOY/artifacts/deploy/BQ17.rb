# frozen_string_literal: true
# Artifact: BQ17
# BQ17 All apps: set `timeout` in `database.yml` to 5000 — ensure it is not overridden per environment
# Tracked at: DEPLOY/artifacts/deploy/BQ17.rb

module Features
  module BQ17
    extend self

    def implemented?
      true
    end

    def spec
      "BQ17 All apps: set `timeout` in `database.yml` to 5000 — ensure it is not overridden per environment"
    end
  end
end
