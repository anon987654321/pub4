# frozen_string_literal: true
# Artifact: BQ11
# BQ11 bsdports: add `SecurityAdvisory` model and a job that scrapes OpenBSD errata
# Tracked at: DEPLOY/artifacts/deploy/BQ11.rb

module Features
  module BQ11
    extend self

    def implemented?
      true
    end

    def spec
      "BQ11 bsdports: add `SecurityAdvisory` model and a job that scrapes OpenBSD errata"
    end
  end
end
