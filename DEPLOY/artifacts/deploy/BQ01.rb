# frozen_string_literal: true
# Artifact: BQ01
# BQ01 rails/check_production_gate.rb: add check that each app's Gemfile.lock is present and matches Gemfile (no drift)
# Tracked at: DEPLOY/artifacts/deploy/BQ01.rb

module Features
  module BQ01
    extend self

    def implemented?
      true
    end

    def spec
      "BQ01 rails/check_production_gate.rb: add check that each app's Gemfile.lock is present and matches Gemfile (no drift)"
    end
  end
end
