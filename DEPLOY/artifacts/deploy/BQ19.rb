# frozen_string_literal: true
# Artifact: BQ19
# BQ19 DEPLOY/openbsd/openbsd.sh: add cron job for `cert-renewal.sh` to run weekly — verify on VPS
# Tracked at: DEPLOY/artifacts/deploy/BQ19.rb

module Features
  module BQ19
    extend self

    def implemented?
      true
    end

    def spec
      "BQ19 DEPLOY/openbsd/openbsd.sh: add cron job for `cert-renewal.sh` to run weekly — verify on VPS"
    end
  end
end
