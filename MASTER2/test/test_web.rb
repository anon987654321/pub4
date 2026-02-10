# frozen_string_literal: true

require_relative "test_helper"

class TestWeb < Minitest::Test
  def test_responds_to_public_api
    assert_respond_to MASTER::Web, :start
    assert_respond_to MASTER::Web, :stop
  end

  def test_web_module_exists
    assert defined?(MASTER::Web), "MASTER::Web should be defined"
  end
end
