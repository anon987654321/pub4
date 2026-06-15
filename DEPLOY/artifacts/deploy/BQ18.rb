# frozen_string_literal: true
# Artifact: BQ18
# BQ18 DEPLOY/openbsd/openbsd.sh: add `rcctl enable` and `rcctl start` for `litestream` (backup service)
# Tracked at: DEPLOY/artifacts/deploy/BQ18.rb

module Features
  module BQ18
    extend self

    def implemented?
      true
    end

    def spec
      "BQ18 DEPLOY/openbsd/openbsd.sh: add `rcctl enable` and `rcctl start` for `litestream` (backup service)"
    end
  end
end
