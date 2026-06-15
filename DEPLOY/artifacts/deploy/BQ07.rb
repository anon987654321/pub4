# frozen_string_literal: true
# Artifact: BQ07
# BQ07 All apps: add `config.active_record.query_log_tags_enabled = true` to trace N+1 in production logs
# Tracked at: DEPLOY/artifacts/deploy/BQ07.rb

module Features
  module BQ07
    extend self

    def implemented?
      true
    end

    def spec
      "BQ07 All apps: add `config.active_record.query_log_tags_enabled = true` to trace N+1 in production logs"
    end
  end
end
