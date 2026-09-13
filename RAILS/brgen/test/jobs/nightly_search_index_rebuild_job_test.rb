# frozen_string_literal: true

require "minitest/mock"
require "test_helper"

class NightlySearchIndexRebuildJobTest < ActiveSupport::TestCase
  def connection_with(fts:, &on_execute)
    connection = Object.new
    connection.define_singleton_method(:data_source_exists?) { |name| fts && name == "posts_fts" }
    connection.define_singleton_method(:execute) { |sql| on_execute&.call(sql) || true }
    connection
  end

  test "rebuilds the posts fts index" do
    executed = false
    connection = connection_with(fts: true) { |sql| executed = sql == "INSERT INTO posts_fts(posts_fts) VALUES('rebuild')" }

    ActiveRecord::Base.stub(:connection, connection) do
      NightlySearchIndexRebuildJob.perform_now
    end

    assert executed
  end

  test "a database without posts_fts says so instead of finishing silently" do
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)

    ActiveRecord::Base.stub(:connection, connection_with(fts: false)) do
      NightlySearchIndexRebuildJob.perform_now
    end

    assert_includes logged.string, "posts_fts does not exist"
  ensure
    Rails.logger = original
  end
end
