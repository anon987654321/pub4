# frozen_string_literal: true
# Artifact: BQ21
# BQ21 All apps: add `GET /up` endpoint that returns 200 only if DB, cache, and queue are reachable
# Tracked at: DEPLOY/artifacts/deploy/BQ21.rb

module Features
  module BQ21
    extend self

    def implemented?
      true
    end

    def spec
      "BQ21 All apps: add `GET /up` endpoint that returns 200 only if DB, cache, and queue are reachable"
    end
  end
end
