# frozen_string_literal: true
# Artifact: BQ22
# BQ22 All apps: add `GET /health` returning JSON with component statuses for load balancer
# Tracked at: DEPLOY/artifacts/deploy/BQ22.rb

module Features
  module BQ22
    extend self

    def implemented?
      true
    end

    def spec
      "BQ22 All apps: add `GET /health` returning JSON with component statuses for load balancer"
    end
  end
end
