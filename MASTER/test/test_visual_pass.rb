# frozen_string_literal: true

require_relative "test_helper"

class VisualPassContractTest < Minitest::Test
  PATH = File.expand_path("../lib/fix/visual_pass.rb", __dir__)

  def source = File.read(PATH)

  def test_visual_pass_uses_the_existing_rendered_measurement_stack
    assert_includes source, "Deploy::GeometryProbe.surfaces"
    assert_includes source, "Deploy::GeometryProbe.with_browser"
    assert_includes source, "Deploy::GeometryProbe.walk"
    refute_includes source, "Selenium::WebDriver"
    refute_includes source, "require \"selenium-webdriver\""
  end

  def test_visual_findings_enter_the_existing_ui_council_and_fix_protocol
    assert_includes source, "mode: :ui"
    assert_includes source, "visual_image:"
    assert_includes source, "visual_context:"
    assert_includes source, "RULE_ID = \"RENDERED_VISUAL_REFINEMENT\""
  end

  def test_visual_targets_are_limited_to_web_surfaces
    assert_includes source, 'relative == "RAILS"'
    assert_includes source, 'relative == "MASTER/web"'
  end
end
