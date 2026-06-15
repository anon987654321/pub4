# frozen_string_literal: true
# Artifact: BQ08
# BQ08 All apps: add `config.action_dispatch.show_exceptions = :none` (exceptions → 500) — document if overridden
# Tracked at: DEPLOY/artifacts/deploy/BQ08.rb

module Features
  module BQ08
    extend self

    def implemented?
      true
    end

    def spec
      "BQ08 All apps: add `config.action_dispatch.show_exceptions = :none` (exceptions → 500) — document if overridden"
    end
  end
end
