# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require File.expand_path("../../MASTER/checks/support/geometry_probe", __dir__)
require_relative "../lib/fix/visual_pass_review_entry"

# Unbounded, the per-pass rendered review rendered all 212 declared surfaces every pass, each with up
# to twelve composition states: thirteen minutes a pass on the 2026-11-05 RAILS run with brgen down.
# The operator's rule (2026-11-06): mobile captures first, and the last to be cut by the cap.
class TestVisualSurfaceCap < Minitest::Test
  Pass = Master::Fix::VisualPass
  Probe = Deploy::GeometryProbe
  SIZES = { "desktop" => [1440, 900], "mobile" => [390, 844], "small" => [320, 568], "narrow" => [360, 740] }.freeze

  def rows(pages: 20, viewports: %w[desktop mobile])
    %w[brgen amber].product((1..pages).to_a, viewports).map do |app, page, viewport|
      width, height = SIZES.fetch(viewport)
      Probe::Surface.new(app:, label: "page#{page}", path: "/", viewport:, port: 4000, width:, height:)
    end
  end

  def pick(pass, surfaces = rows)
    visual = Pass.new(agent: Object.new, root: File.expand_path("..", Master::ROOT))
    Probe.stub(:surfaces, surfaces) { visual.send(:selected_surfaces, target: "RAILS", pass:) }
  end

  def test_a_capped_pass_takes_mobile_captures_before_any_desktop_one
    picked = pick(1)

    assert_equal 24, picked.size
    assert(picked.all? { |surface| surface.viewport == "mobile" }, picked.map(&:id).inspect)
  end

  def test_desktop_only_fills_the_room_left_after_every_mobile_capture
    surfaces = rows(pages: 5)
    picked = pick(1, surfaces)
    mobile = surfaces.select { |surface| surface.viewport == "mobile" }

    assert_equal mobile.map(&:id).sort, picked.first(mobile.size).map(&:id).sort
    assert(picked.drop(mobile.size).all? { |surface| surface.viewport == "desktop" })
  end

  def test_the_phone_width_comes_before_the_narrower_mobile_widths
    picked = pick(1, rows(pages: 2, viewports: %w[small desktop narrow mobile]))

    assert_equal [390, 390, 390, 390, 360, 360, 360, 360, 320, 320, 320, 320, 1440, 1440, 1440, 1440],
                 picked.map(&:width)
  end

  def test_consecutive_passes_reach_every_mobile_surface
    seen = (1..2).flat_map { |pass| pick(pass).map(&:id) }.uniq

    assert_equal rows.select { |surface| surface.viewport == "mobile" }.map(&:id).sort, seen.sort
  end

  def test_a_review_still_renders_the_whole_set_mobile_first
    visual = Pass.new(agent: Object.new, root: File.expand_path("..", Master::ROOT))
    all = Probe.stub(:surfaces, rows) { visual.review_surfaces(target: "RAILS") }

    assert_equal 80, all.size
    assert_equal %w[mobile desktop], all.map(&:viewport).chunk_while { |a, b| a == b }.map(&:first)
  end

  def test_the_declared_inventory_is_mobile_first
    widths = Probe.mobile_first(rows).map(&:width)

    assert_equal widths.sort, widths
  end
end
