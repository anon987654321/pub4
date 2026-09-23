# frozen_string_literal: true

require "minitest/autorun"

class TestModernWebPlatformEvidence < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_web_platform_probe_is_mobile_only_and_non_mutating
    source = read("../RAILS/gates/support/web_platform_probe.rb")
    assert_includes source, "return {} unless surface.viewport == \"mobile\""
    assert_includes source, "cdp.evaluate(SCRIPT)"
    refute_includes source, "cdp.click"
    refute_includes source, "cdp.navigate"
  end

  def test_visual_pass_feeds_platform_evidence_into_review
    source = read("lib/fix/visual_pass.rb")
    assert_includes source, 'require_relative "../../../RAILS/gates/support/web_platform_probe"'
    assert_includes source, "platform = Deploy::WebPlatformProbe.run"
    assert_includes source, 'web-platform=#{capture[:platform]'
  end

  def test_modern_web_laws_are_part_of_visual_constitution
    laws = read("law/css.rb")
    visual = read("lib/fix/visual_usability.rb")
    %w[
      INTRINSIC_LAYOUT
      CONTAINER_RESPONSIVENESS
      MODERN_FORMS
      NATIVE_DISCLOSURE
      ANCHOR_RELATIONSHIPS
      SCOPED_CSS
      MOBILE_VIEWPORT
      SCROLL_INTEGRITY
      MOTION_ACCESSIBILITY
      NAVIGATION_CONTINUITY
    ].each do |id|
      assert_includes laws, "Law.define(:#{id})"
      assert_includes visual, id
    end
  end
end
