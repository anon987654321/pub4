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
    assert_includes source, "Deploy::CompositionProbe.capture"
    assert_includes source, "MAX_COMPOSITION_STATES"
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

  def test_composition_probe_is_application_agnostic
    refute_includes source, "brgen"
    composition = File.read(File.expand_path("../../RAILS/gates/support/composition_probe.rb", __dir__))
    assert_includes composition, "button, summary, [role='button']"
    assert_includes composition, "MASTER visual probe"
    assert_includes composition, "GeometryProbe.measure_current"
    assert_includes composition, "data-master-composition-ignore"
    assert_includes composition, "MASTER_VISUAL_COMPOSITION_PAIRS"
    refute_includes composition, "rescue StandardError"
  end

  def test_visual_findings_must_be_addressable
    assert_includes source, "surface = pick[SURFACE_RE"
    assert_includes source, "viewport = pick[VIEWPORT_RE"
    assert_includes source, "source_text_line"
    assert_includes source, "return unless surface && viewport && (selector || text_anchor)"
  end
end
