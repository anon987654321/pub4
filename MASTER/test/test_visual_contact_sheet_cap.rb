# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../gates/support/geometry_probe", __dir__)
require File.expand_path("../lib/fix/visual_contact_sheet", __dir__)

# A sweep of hundreds of states made the contact sheet taller than Chrome will
# screenshot ("Page is too large"), which ended a full brgen review after an hour
# of capture. The sheet now holds a bounded number of figures, resting first.
class TestVisualContactSheetCap < Minitest::Test
  PNG = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*")

  def capture(dir, label, state)
    shot = File.join(dir, "#{label}.png")
    File.binwrite(shot, PNG)
    surface = Deploy::GeometryProbe::Surface.new(app: "brgen", label:, path: "/", viewport: "mobile", port: 1)
    { surface:, payload: { "composition" => { "state" => state } }, screenshot: shot, journeys: [] }
  end

  def test_figures_are_capped_and_resting_renders_come_first
    Dir.mktmpdir("sheet") do |dir|
      captures = Array.new(300) { |i| capture(dir, "s#{i}", i < 290 ? "stress" : "resting") }
      html = Master::Fix::VisualContactSheet.new(dir:, root: dir).send(:page, captures)

      assert_equal Master::Fix::VisualContactSheet::MAX_FIGURES, html.scan("<figure>").size
      assert_match(%r{brgen/s299/mobile \| mobile}, html)
      assert_includes html, "first #{Master::Fix::VisualContactSheet::MAX_FIGURES} figures"
    end
  end

  def test_a_small_sweep_is_shown_whole
    Dir.mktmpdir("sheet") do |dir|
      captures = Array.new(3) { |i| capture(dir, "s#{i}", "resting") }
      html = Master::Fix::VisualContactSheet.new(dir:, root: dir).send(:page, captures)

      assert_equal 3, html.scan("<figure>").size
      refute_includes html, "first"
    end
  end
end
