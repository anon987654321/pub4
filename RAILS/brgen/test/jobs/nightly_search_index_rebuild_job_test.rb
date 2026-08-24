# frozen_string_literal: true

require "test_helper"

class NightlySearchIndexRebuildJobTest < ActiveSupport::TestCase
  test "rebuilds the posts fts index" do
    executed = false
    connection = Object.new
    connection.define_singleton_method(:data_source_exists?) { |name| name == "posts_fts" }
    connection.define_singleton_method(:execute) do |sql|
      executed = sql == "INSERT INTO posts_fts(posts_fts) VALUES('rebuild')"
      true
    end

    ActiveRecord::Base.stub(:connection, connection) do
      NightlySearchIndexRebuildJob.perform_now
    end

    assert executed
  end
end
