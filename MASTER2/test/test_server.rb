# frozen_string_literal: true

require_relative "test_helper"

class TestServer < Minitest::Test
  def test_responds_to_public_api
    assert_respond_to MASTER::Server, :start
    assert_respond_to MASTER::Server, :stop
  end

  def test_server_module_exists
    assert defined?(MASTER::Server), "MASTER::Server should be defined"
  end
end
