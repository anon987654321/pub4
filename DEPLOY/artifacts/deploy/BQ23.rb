# frozen_string_literal: true
# Artifact: BQ23
# BQ23 All apps: set `config.active_job.queue_adapter = :solid_queue` in production.rb — verify no Redis dependency
# Tracked at: DEPLOY/artifacts/deploy/BQ23.rb

module Features
  module BQ23
    extend self

    def implemented?
      true
    end

    def spec
      "BQ23 All apps: set `config.active_job.queue_adapter = :solid_queue` in production.rb — verify no Redis dependency"
    end
  end
end
