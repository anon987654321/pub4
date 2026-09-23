# frozen_string_literal: true

require_relative "test_helper"

class VisualPassContractTest < Minitest::Test
  PATH = File.expand_path("../lib/fix/visual_pass.rb", __dir__)

  def source = File.read(PATH)

  def test_visual_pass_uses_the_existing_geometry_probe
    assert_includes source, "Deploy::GeometryProbe.surfaces"
    assert_includes source, "Deploy::GeometryProbe.with_browser"
    assert_includes source, "Deploy::GeometryProbe.walk"
    refute_includes source, "Selenium::WebDriver"
    refute_includes source, "selenium-webdriver"
  end

  def test_visual_review_enters_the_existing_council_and_fix_protocol
    assert_includes source, "mode: :ui"
    assert_includes source, "visual_image:"
    assert_includes source, "visual_context:"
    assert_includes source, "RULE_ID = \"RENDERED_VISUAL_REFINEMENT\""
    assert_includes source, "council: council_value"
  end

  def test_visual_findings_must_be_addressable
    assert_includes source, "surface = pick[SURFACE_RE"
    assert_includes source, "viewport = pick[VIEWPORT_RE"
    assert_includes source, "source_text_line"
    assert_includes source, "return unless surface && viewport && (selector || text_anchor)"
  end
end
