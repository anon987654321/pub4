# frozen_string_literal: true
# Artifact: BQ20
# BQ20 DEPLOY/openbsd/openbsd.sh: after Stage 2, run `verify_deploy_identity.rb` and fail if any error
# Tracked at: DEPLOY/artifacts/deploy/BQ20.rb

module Features
  module BQ20
    extend self

    def implemented?
      true
    end

    def spec
      "BQ20 DEPLOY/openbsd/openbsd.sh: after Stage 2, run `verify_deploy_identity.rb` and fail if any error"
    end
  end
end
