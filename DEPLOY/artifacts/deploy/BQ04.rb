# frozen_string_literal: true
# Artifact: BQ04
# BQ04 All apps: add `config.assume_ssl = true` — verify no `config.force_ssl = true` anywhere
# Tracked at: DEPLOY/artifacts/deploy/BQ04.rb

module Features
  module BQ04
    extend self

    def implemented?
      true
    end

    def spec
      "BQ04 All apps: add `config.assume_ssl = true` — verify no `config.force_ssl = true` anywhere"
    end
  end
end
