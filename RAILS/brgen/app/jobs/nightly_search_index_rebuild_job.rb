# frozen_string_literal: true

class NightlySearchIndexRebuildJob < ApplicationJob
  queue_as :bulk

  def perform
    return unless ActiveRecord::Base.connection.data_source_exists?("posts_fts")

    ActiveRecord::Base.connection.execute("INSERT INTO posts_fts(posts_fts) VALUES('rebuild')")
  end
end
