# frozen_string_literal: true

require "minitest/autorun"

class TestRenderedVisualConvergence < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_geometry_probe_exposes_first_screen_composition_facts
    walk = read("../RAILS/gates/support/geometry_probe/walk.js")
    assert_includes walk, "const firstScreen = (() => {"
    assert_includes walk, "largest_area_ratio"
    assert_includes walk, "weak-heading-scale"
    assert_includes walk, "many-first-screen-actions"
    assert_includes walk, "text_box_width_em_approx"
    refute_includes walk, "text_measures_ch_approx"
  end

  def test_visual_contract_uses_the_canonical_cdp_substrate
    source = read("../RAILS/gates/visual_contract.rb")
    assert_includes source, 'require_relative "support/geometry_probe"'
    assert_includes source, "GeometryProbe.with_browser"
    assert_includes source, "Master::Io::Exec.capture3"
    refute_includes source, "Open3.capture3"
    assert_includes source, "ROOT = File.expand_path(\"../..\", __dir__).freeze"
    refute_includes source, 'require "selenium-webdriver"'
    refute_includes source, "Selenium::WebDriver"
    refute_includes source, "ACCESSIBILITY_PROBE = <<~JS\n    return ["
  end

  def test_rendered_repairs_require_a_stable_anchor
    source = read("lib/fix/visual_pass.rb")
    assert_includes source, "SELECTOR_RE"
    assert_includes source, "TEXT_ANCHOR_RE"
    assert_includes source, "SURFACE_RE"
    assert_includes source, "VIEWPORT_RE"
    assert_includes source, "return unless surface && viewport"
  end

  def test_visual_pass_cannot_guess_an_unanchored_source_file
    source = read("lib/fix/visual_pass.rb")
    refute_includes source, "file ||= sources.first"
    assert_includes source, "return unless surface && viewport"
    assert_includes source, "return unless line"
  end

  def test_cdp_console_evidence_can_be_reset_between_pages
    source = read("../RAILS/gates/support/cdp_session.rb")
    assert_includes source, "def clear_events = @events.clear"
    assert_includes read("../RAILS/gates/visual_contract.rb"), "cdp.clear_events"
  end

  def test_ui_critique_excludes_judge_from_issue_numbering
    source = read("lib/review/council/critique.rb")
    assert_includes source, 'reject { |entry| entry[:persona].to_s == "Judge" }'
    assert_includes source, "output VISUAL_CLEAN exactly"
  end
end
