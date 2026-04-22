# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/boot"

class TestBoot < Minitest::Test
  def test_web_url_includes_token_when_present
    url = MASTER::Boot.web_url(12_345, token: "abc123")

    assert_equal "http://localhost:12345/?token=abc123", url
  end

  def test_web_url_omits_token_when_blank
    url = MASTER::Boot.web_url(12_345, token: "")

    assert_equal "http://localhost:12345", url
  end
end
