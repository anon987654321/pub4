# frozen_string_literal: true
# Artifact: BQ14
# BQ14 hjerterom: add `Donor` model (table already created in migration) and wire to `Donation`
# Tracked at: DEPLOY/artifacts/deploy/BQ14.rb

module Features
  module BQ14
    extend self

    def implemented?
      true
    end

    def spec
      "BQ14 hjerterom: add `Donor` model (table already created in migration) and wire to `Donation`"
    end
  end
end
