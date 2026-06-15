# frozen_string_literal: true
# Artifact: BQ03
# BQ03 All apps: ensure `config.active_storage.service = :local` is used in production; S3/mirror only via explicit override
# Tracked at: DEPLOY/artifacts/deploy/BQ03.rb

module Features
  module BQ03
    extend self

    def implemented?
      true
    end

    def spec
      "BQ03 All apps: ensure `config.active_storage.service = :local` is used in production; S3/mirror only via explicit override"
    end
  end
end
