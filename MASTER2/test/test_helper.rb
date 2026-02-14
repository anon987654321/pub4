# frozen_string_literal: true

require "minitest/autorun"
require 'tmpdir'
require_relative "../lib/master"

# Stoplight is now always available since it's in the Gemfile
STOPLIGHT_AVAILABLE = true

# Shared test setup
module TestHelper
  def setup_db
    @test_db_dir = Dir.mktmpdir
    MASTER::DB.setup(path: @test_db_dir)
  end

  def teardown_db
    FileUtils.rm_rf(@test_db_dir) if @test_db_dir && Dir.exist?(@test_db_dir)
  end
end

class Minitest::Test
  include TestHelper
end
