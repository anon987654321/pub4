# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

# Shared test setup
module TestHelper
  def setup_db
    MASTER::DB.setup(path: ":memory:")
  end
end

class Minitest::Test
  include TestHelper
end
