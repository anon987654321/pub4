# frozen_string_literal: true

require "minitest/autorun"

class TestMobileNavigationJourneys < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source
    File.read(File.join(ROOT, "../RAILS/gates/support/mobile_journey_probe.rb"), encoding: "UTF-8")
  end

  def test_discovers_only_safe_same_origin_get_navigation
    code = source
    assert_includes code, "url.origin !== origin"
    assert_includes code, "data-method"
    assert_includes code, "data-turbo-method"
    assert_includes code, '/\\b(logout|signout|delete|destroy|remove|unsubscribe)\\b/i'
  end

  def test_captures_return_path
    assert_includes source, 'kind" => "navigation_back"'
    assert_includes source, '"from" => after["url"]'
    assert_includes source, '"to" => surface.url'
  end

  def test_state_signature_covers_non_text_state
    assert_includes source, "aria-expanded"
    assert_includes source, ":popover-open"
    assert_includes source, "document.activeElement"
  end
end
