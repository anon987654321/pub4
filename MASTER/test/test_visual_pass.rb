# frozen_string_literal: true

require_relative "test_helper"

class VisualPassContractTest < Minitest::Test
  PATH = File.expand_path("../lib/fix/visual_pass.rb", __dir__)

  def source = File.read(PATH)

  def test_visual_pass_uses_the_existing_rendered_measurement_stack
    assert_includes source, "Deploy::GeometryProbe.surfaces"
    assert_includes source, "Deploy::GeometryProbe.with_browser"
    assert_includes source, "Deploy::GeometryProbe.walk"
    assert_includes source, "Deploy::GeometryProbe.measure_current"
    assert_includes source, "capture_brgen_composition"
    assert_includes source, "composer_open"
    assert_includes source, "messenger_open"
    refute_includes source, "Selenium::WebDriver"
    refute_includes source, "require \"selenium-webdriver\""
  end

  def test_visual_findings_enter_the_existing_ui_council_and_fix_protocol
    assert_includes source, "mode: :ui"
    assert_includes source, "visual_image:"
    assert_includes source, "visual_context:"
    assert_includes source, "RULE_ID = \"RENDERED_VISUAL_REFINEMENT\""
    assert_includes File.read(File.expand_path("../../RAILS/gates/data/geometry_surfaces.yml", __dir__)), "app: master"
  end

  def test_visual_targets_are_limited_to_web_surfaces
    assert_includes source, 'relative == "RAILS"'
    assert_includes source, 'relative == "MASTER/web"'
  end

  def test_brgen_composition_is_page_wide_not_feature_isolated
    assert_includes source, 'surface.app == "brgen" && surface.label == "core"'
    assert_includes source, 'co_resident'
    assert_includes source, "%w[feed posts composer messenger]"
    assert_includes source, 'measure_current(cdp, state_surface)'
  end

  def test_visual_findings_must_be_addressable
    assert_includes source, "surface = pick[SURFACE_RE"
    assert_includes source, "viewport = pick[VIEWPORT_RE"
    assert_includes source, "source_text_line"
    assert_includes source, "return unless surface && viewport && (selector || text_anchor)"
  end
end
