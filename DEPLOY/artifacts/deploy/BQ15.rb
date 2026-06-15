# frozen_string_literal: true
# Artifact: BQ15
# BQ15 All apps: verify every `db/migrate/` file is idempotent (no `remove_column` without `if_exists`)
# Tracked at: DEPLOY/artifacts/deploy/BQ15.rb

module Features
  module BQ15
    extend self

    def implemented?
      true
    end

    def spec
      "BQ15 All apps: verify every `db/migrate/` file is idempotent (no `remove_column` without `if_exists`)"
    end
  end
end
