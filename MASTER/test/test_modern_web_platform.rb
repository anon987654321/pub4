# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/fix/visual_pass"
# VisualPass#run loads the probe only when it runs; capture_resting needs it here.
require_relative "../../MASTER/gates/support/geometry_probe"

# The web-platform probe gathers mobile evidence without touching the page, the
# visual pass hands that evidence to the council, and the modern-web laws are
# part of what the council is told to apply.
class TestModernWebPlatformEvidence < Minitest::Test
  Surface = Struct.new(:id, :url, :viewport, keyword_init: true)

  # Records every call, so "only evaluated" is a measurement.
  class RecordingCdp
    attr_reader :calls

    def initialize(reply)
      @reply = reply
      @calls = []
    end

    def evaluate(_script)
      @calls << :evaluate
      @reply
    end

    def screenshot(*, **) = @calls << :screenshot

    def method_missing(name, *, **) = @calls << name
    def respond_to_missing?(*) = true
  end

  def test_web_platform_probe_is_mobile_only_and_non_mutating
    desktop = RecordingCdp.new("{}")
    assert_equal({}, Deploy::WebPlatformProbe.run(desktop, Surface.new(id: "d", viewport: "desktop")))
    assert_empty desktop.calls, "the probe touched a desktop surface"

    mobile = RecordingCdp.new(JSON.generate("overflow" => { "document" => false }, "disclosure" => true))
    payload = Deploy::WebPlatformProbe.run(mobile, Surface.new(id: "m", viewport: "mobile"))
    assert_equal true, payload["disclosure"]
    assert_equal [:evaluate], mobile.calls, "the probe did more than read the page"
  end

  def test_visual_pass_feeds_platform_evidence_into_review
    pass = Master::Fix::VisualPass.new(agent: nil, root: File.expand_path("..", __dir__))
    surface = Surface.new(id: "brgen/mobile", url: "http://localhost/", viewport: "mobile")
    platform = { "viewport" => { "width" => 390 }, "disclosure" => true, "small_form_text" => 2 }
    payload = { "composition" => { "state" => "resting" }, "visual" => {} }

    capture = Dir.mktmpdir do |dir|
      pass.instance_variable_set(:@dir, dir)
      Deploy::GeometryProbe.stub(:walk, payload) do
        Deploy::GeometryProbe.stub(:ok?, true) do
          Deploy::MobileJourneyProbe.stub(:run, []) do
            Deploy::WebPlatformProbe.stub(:run, platform) { pass.send(:capture_resting, RecordingCdp.new("{}"), surface) }
          end
        end
      end
    end
    assert_equal platform, capture[:platform]

    row = pass.send(:context_row, capture)
    assert_includes row, "web-platform=disclosure=true, small_form_text=2"
    refute_includes row, "viewport=", "the viewport is the surface's, not platform evidence"
  end

  def test_unanchored_council_picks_cannot_be_reported_as_clean
    pass = Master::Fix::VisualPass.new(agent: nil, root: File.expand_path("..", __dir__))
    critique = Master::Result.ok(cherry_picks: ["tighten the hero spacing somewhere"])

    result = pass.send(:anchored_findings, critique, [], {})
    assert_kind_of Master::Result, result
    assert result.err?
    assert_equal :inconclusive, result.category
    assert_includes result.message, "none could be anchored to source evidence"

    assert_equal [], pass.send(:anchored_findings, Master::Result.ok(cherry_picks: []), [], {}),
                 "no picks is a clean pass, not an inconclusive one"
  end

  MODERN_LAWS = %w[
    INTRINSIC_LAYOUT CONTAINER_RESPONSIVENESS MODERN_FORMS NATIVE_DISCLOSURE ANCHOR_RELATIONSHIPS
    SCOPED_CSS MOBILE_VIEWPORT SCROLL_INTEGRITY MOTION_ACCESSIBILITY NAVIGATION_CONTINUITY
  ].freeze

  def test_modern_web_laws_are_part_of_visual_constitution
    context = Master::Fix::VisualUsability.context

    MODERN_LAWS.each do |id|
      law = Law.rules.fetch(id.to_sym) { flunk "#{id} is not a law" }
      refute_empty law.ask.to_s.strip, "#{id} asks nothing"
      assert_includes Master::Fix::VisualUsability.ids, id
      assert_match(/^#{id}: #{Regexp.escape(law.ask)} Fix: /, context)
    end
  end
end
