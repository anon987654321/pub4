# frozen_string_literal: true

require "minitest/autorun"

class WebScreenshotSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  TOOL = File.join(ROOT, "bin", "web-screenshot")

  def source
    File.read(TOOL)
  end

  def test_screenshot_tool_exists
    assert File.exist?(TOOL)
  end

  def test_screenshot_tool_uses_headless_browser
    assert_includes source, "--headless=new"
    assert_includes source, "--screenshot="
    assert_includes source, "chromium"
  end

  def test_screenshot_tool_writes_reports_path_by_default
    assert_includes source, "reports"
    assert_includes source, "screenshots"
    assert_includes source, "home.png"
  end

  def test_screenshot_tool_fails_if_browser_missing
    assert_includes source, "chromium/google-chrome not found"
    assert_includes source, "URL required"
  end
end
