# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestServer < Minitest::Test
  def setup
    @server = MASTER::Server.new
  end

  def test_auth_token_defined
    assert MASTER::Server::AUTH_TOKEN
    assert_kind_of String, MASTER::Server::AUTH_TOKEN
  end

  def test_server_initializes_with_port
    assert @server.port > 0
    assert @server.port <= 65535
  end

  def test_server_url_format
    url = @server.url
    assert_match(/^http:\/\/localhost:\d+$/, url)
  end

  def test_output_queue_exists
    assert_kind_of Queue, @server.output_queue
  end

  def test_views_dir_constant
    assert MASTER::Server::VIEWS_DIR
    assert_kind_of String, MASTER::Server::VIEWS_DIR
  end

  def test_server_not_running_initially
    refute @server.running?
  end

  def test_running_predicate_reflects_state
    # Test that running? reflects the internal state correctly
    initial_state = @server.running?
    refute initial_state, "Server should not be running initially"
    
    # Note: We can't actually start the server in tests (it would bind a port)
    # but we've verified the accessor works for the initial false state
  end

  def test_localhost_binding
    # This test verifies the server is configured to bind to localhost
    # We can't actually start the server in test, but we can verify configuration
    assert @server.url.include?("localhost"), "Server should use localhost"
  end
end
