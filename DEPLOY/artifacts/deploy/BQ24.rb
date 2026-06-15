# frozen_string_literal: true
# Artifact: BQ24
# BQ24 All apps: add `config/recurring.yml` with `clear_solid_queue_finished_jobs` (copy to apps that are missing it)
# Tracked at: DEPLOY/artifacts/deploy/BQ24.rb

module Features
  module BQ24
    extend self

    def implemented?
      true
    end

    def spec
      "BQ24 All apps: add `config/recurring.yml` with `clear_solid_queue_finished_jobs` (copy to apps that are missing it)"
    end
  end
end
