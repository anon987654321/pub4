# frozen_string_literal: true
# Artifact: BQ02
# BQ02 rails/check_production_gate.rb: verify `config.host_authorization` excludes `/up` for all apps
# Tracked at: DEPLOY/artifacts/deploy/BQ02.rb

module Features
  module BQ02
    extend self

    def implemented?
      true
    end

    def spec
      "BQ02 rails/check_production_gate.rb: verify `config.host_authorization` excludes `/up` for all apps"
    end
  end
end
