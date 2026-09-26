# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "../lib/fix/visual_custody"
require_relative "../gates/support/geometry_probe"

class TestVisualCustody < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def surface
    Deploy::GeometryProbe::Surface.new(
      app: "brgen",
      label: "messenger",
      host: "messenger.brgen.no",
      path: "/",
      viewport: "desktop",
      width: 1440,
      height: 900,
      snapshot: true,
      port: nil,
      profile: nil,
    )
  end

  def capture(payload)
    { surface:, payload: }
  end

  def baseline
    path = File.join(ROOT, "gates", "data", "layout_snapshots", "brgen-messenger-desktop.json")
    JSON.parse(File.read(path))
  end

  def test_matching_snapshot_is_preserved
    payload = baseline.merge("status" => 200, "composition" => { "state" => "resting" })
    custody = Master::Fix::VisualCustody.new(root: ROOT, surfaces: [surface])

    result = custody.preflight!([capture(payload)])

    assert result.ok?, result.message
  end

  def test_one_pixel_beyond_snapshot_tolerance_is_blocked
    payload = baseline.merge("status" => 200, "composition" => { "state" => "resting" })
    payload["elements"] = payload["elements"].map do |element|
      next element unless element["key"] == "#main-content"

      element.merge("rect" => element.fetch("rect").merge("x" => element.fetch("rect").fetch("x") + 3))
    end
    custody = Master::Fix::VisualCustody.new(root: ROOT, surfaces: [surface])

    result = custody.preflight!([capture(payload)])

    refute result.ok?
    assert_includes result.message, "visual custody"
    assert_includes result.message, "reflow"
  end

  def test_missing_baseline_is_inconclusive_not_clean
    other_surface = surface.dup.tap { |row| row.label = "does-not-exist" }
    payload = baseline.merge("status" => 200, "composition" => { "state" => "resting" })
    custody = Master::Fix::VisualCustody.new(root: ROOT, surfaces: [other_surface])

    result = custody.preflight!([capture(payload)])

    refute result.ok?
    assert_equal :inconclusive, result.category
    assert_includes result.message, "missing committed baseline"
  end
end
