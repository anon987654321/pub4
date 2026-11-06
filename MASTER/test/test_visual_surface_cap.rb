# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require File.expand_path("../../MASTER/checks/support/geometry_probe", __dir__)
require_relative "../lib/fix/visual_pass_review_entry"

# Unbounded, the per-pass rendered review rendered all 212 declared surfaces every pass, each with up
# to twelve composition states: thirteen minutes a pass on the 2026-11-05 RAILS run with brgen down.
class TestVisualSurfaceCap < Minitest::Test
  Pass = Master::Fix::VisualPass
  Probe = Deploy::GeometryProbe

  def rows
    %w[brgen amber].product((1..20).to_a, %w[mobile desktop]).map do |app, page, viewport|
      Probe::Surface.new(app:, label: "page#{page}", path: "/", viewport:, port: 4000, width: 390, height: 844)
    end
  end

  def pick(pass)
    visual = Pass.new(agent: Object.new, root: File.expand_path("..", Master::ROOT))
    Probe.stub(:surfaces, rows) { visual.send(:selected_surfaces, target: "RAILS", pass:) }
  end

  def test_a_pass_renders_a_bounded_share_that_keeps_every_apps_core
    picked = pick(1)

    assert_equal 24, picked.size
    %w[brgen amber].product(%w[mobile desktop]).each do |app, viewport|
      assert(picked.any? { |surface| surface.app == app && surface.viewport == viewport }, "#{app} #{viewport}")
    end
  end

  def test_consecutive_passes_reach_every_surface
    seen = (1..4).flat_map { |pass| pick(pass).map(&:id) }.uniq

    assert_equal rows.map(&:id).sort, seen.sort
  end

  def test_a_review_still_renders_the_whole_set
    visual = Pass.new(agent: Object.new, root: File.expand_path("..", Master::ROOT))

    assert_equal 80, Probe.stub(:surfaces, rows) { visual.review_surfaces(target: "RAILS") }.size
  end
end
