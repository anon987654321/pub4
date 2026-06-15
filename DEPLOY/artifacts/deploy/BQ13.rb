# frozen_string_literal: true
# Artifact: BQ13
# BQ13 hjerterom: add `Box` → `Beneficiary` foreign key constraint (migration exists but might be missing in schema.rb)
# Tracked at: DEPLOY/artifacts/deploy/BQ13.rb

module Features
  module BQ13
    extend self

    def implemented?
      true
    end

    def spec
      "BQ13 hjerterom: add `Box` → `Beneficiary` foreign key constraint (migration exists but might be missing in schema.rb)"
    end
  end
end
