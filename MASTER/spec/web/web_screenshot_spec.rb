# frozen_string_literal: true

require "minitest/autorun"

class WebScreenshotSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  # 8a6fb839c moved the tool out of bin/ and renamed it; this spec kept
  # pointing at the old path, so four assertions about a real contract were
  # failing on File.read rather than on anything the tool does.
  TOOL = File.join(ROOT, "tools", "web_screenshot.rb")

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
