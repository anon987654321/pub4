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

  def capture(payload, on: surface)
    { surface: on, payload: }
  end

  def raw_payload
    data = baseline
    {
      "title" => data["title"],
      "vw" => data.fetch("viewport").fetch(0),
      "vh" => data.fetch("viewport").fetch(1),
      "scroll_width" => data["scroll_width"],
      "client_width" => data.fetch("viewport").fetch(0),
      "h1_count" => data["h1_count"],
      "landmarks" => data["landmarks"],
      "first_screen" => data["first_screen"],
      "elements" => data.fetch("elements").map do |element|
        # The snapshot keeps neither visibility nor role: distill() dropped them
        # when it wrote the baseline and reads them back from the probe. A
        # generic role stands in for the one the probe reports on elements that
        # are not structural tags, which distill keeps only by role.
        element.merge("visible" => true, "onscreen" => true, "role" => "generic")
      end,
      "status" => 200,
      "composition" => { "state" => "resting" },
    }
  end

  def baseline
    path = File.join(ROOT, "gates", "data", "layout_snapshots", "brgen-messenger-desktop.json")
    JSON.parse(File.read(path))
  end

  def test_matching_snapshot_is_preserved
    payload = raw_payload
    custody = Master::Fix::VisualCustody.new(root: ROOT, surfaces: [surface])

    result = custody.preflight!([capture(payload)])

    assert result.ok?, (result.message unless result.ok?)
  end

  def test_one_pixel_beyond_snapshot_tolerance_is_blocked
    payload = raw_payload
    payload["elements"] = payload["elements"].map do |element|
      next element unless element["key"] == "#main-content"

      element.merge("rect" => element.fetch("rect").merge("x" => element.fetch("rect").fetch("x") + 3))
    end
    custody = Master::Fix::VisualCustody.new(root: ROOT, surfaces: [surface])

    result = custody.preflight!([capture(payload)])

    refute result.ok?
    assert_includes result.message, "visual custody"
    assert_includes result.message, "nudge: #main-content: x 0→3"
  end

  def test_missing_baseline_is_inconclusive_not_clean
    other_surface = surface.dup.tap { |row| row.label = "does-not-exist" }
    payload = raw_payload
    custody = Master::Fix::VisualCustody.new(root: ROOT, surfaces: [other_surface])

    result = custody.preflight!([capture(payload, on: other_surface)])

    refute result.ok?
    assert_equal :inconclusive, result.category
    assert_includes result.message, "missing committed baseline"
  end
end
