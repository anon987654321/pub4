# frozen_string_literal: true

class NightlySearchIndexRebuildJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: "search-index-rebuild", duration: 1.hour, on_conflict: :discard

  def perform
    unless ActiveRecord::Base.connection.data_source_exists?("posts_fts")
      # A database built from schema.rb has no FTS5 table (schema_format :ruby
      # cannot express one), so say so rather than finish green having done nothing.
      Rails.logger.warn("[search_index_rebuild] skipped: posts_fts does not exist")
      return
    end

    ActiveRecord::Base.connection.execute("INSERT INTO posts_fts(posts_fts) VALUES('rebuild')")
  end
end
