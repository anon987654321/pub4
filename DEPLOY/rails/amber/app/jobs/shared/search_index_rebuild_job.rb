# frozen_string_literal: true

module Shared
  class SearchIndexRebuildJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: ->(*_) { "search-rebuild" }

    def perform(model_name = nil)
      Shared::SearchIndex.rebuild!(model_name)
    rescue NameError
      Rails.logger.info("[search_index] demo mode — no index configured")
    end
  end
end