# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeMode < Minitest::Test
  def test_summary_includes_safe_and_visitor_defaults
    saved = %w[MASTER_SAFE_MODE MASTER_WEB].to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV["MASTER_SAFE_MODE"] = "1"
    ENV["MASTER_WEB"] = "0"
    line = Master::CLI::RuntimeMode.summary(config: { "web_token" => "" })
    assert_includes line, "safe"
    assert_includes line, "visitor"
    assert_includes line, "cli"
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
