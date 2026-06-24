# frozen_string_literal: true

require 'test_helper'

class NightlySearchIndexRebuildJobTest < ActiveSupport::TestCase
  test 'rebuilds the posts fts index' do
    connection = Minitest::Mock.new
    connection.expect(:data_source_exists?, true, ['posts_fts'])
    connection.expect(:execute, true, ["INSERT INTO posts_fts(posts_fts) VALUES('rebuild')"])

    ActiveRecord::Base.stub(:connection, connection) do
      NightlySearchIndexRebuildJob.perform_now
    end

    connection.verify
  end
end
