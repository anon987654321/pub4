# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "master"
require_relative "../lib/fix/visual_pass"
# VisualPass#run loads the probe only when it runs; capture_resting needs it here.
require_relative "../checks/support/geometry_probe"
# Law loads lazily inside VisualUsability; tests that read it directly cannot rely on run order.
require File.join(Master::ROOT, "law", "definition")
Law.load_all(File.join(Master::ROOT, "law")) if Law.definitions.empty?

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

  def test_geometry_walk_marks_only_rectangles_intersecting_viewport
    expression = Deploy::GeometryProbe::WALK[/onscreen:\s*(.+?),\s*\n\s*hit:/m, 1]
    refute_nil expression, "geometry walk must expose its viewport-intersection predicate"

    script = <<~JS
      const onscreen = (r, vw, vh) => (#{expression});
      const cases = [
        [{ left: 10, right: 90, top: 10, bottom: 40 }, 100, 100, true],
        [{ left: 10, right: 90, top: 110, bottom: 140 }, 100, 100, false],
        [{ left: 10, right: 90, top: -20, bottom: 10 }, 100, 100, true],
        [{ left: -20, right: 10, top: 10, bottom: 40 }, 100, 100, true],
        [{ left: 110, right: 140, top: 10, bottom: 40 }, 100, 100, false],
        [{ left: 10, right: 90, top: -140, bottom: -110 }, 100, 100, false]
      ];
      for (const [rect, width, height, expected] of cases) {
        if (Boolean(onscreen(rect, width, height)) !== expected) process.exit(1);
      }
    JS
    _stdout, stderr, status = Open3.capture3("node", "-e", script)
    assert status.success?, "viewport intersection cases failed: #{stderr}"
  rescue Errno::ENOENT
    skip "node is unavailable; JavaScript viewport predicate not executed"
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
          Deploy::MobileJourneyProbe.stub(:measure, { "actions" => [] }) do
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
    BASELINE_COMPATIBILITY CORE_WEB_VITALS WEB_PLATFORM_DEFAULTS
    MOBILE_ACCESSIBILITY_DEFAULTS PWA_RESILIENCE_DEFAULTS
  ].freeze

  def test_modern_web_laws_are_part_of_visual_constitution
    context = Master::Fix::VisualUsability.context

    MODERN_LAWS.each do |id|
      law = Law.definitions.fetch(id.to_sym) { flunk "#{id} is not a law" }
      refute_empty law.ask.to_s.strip, "#{id} asks nothing"
      assert_includes Master::Fix::VisualUsability.ids, id
      assert_match(/^#{id}: #{Regexp.escape(law.ask)} Fix: /, context)
    end
  end

  def test_context_resolves_laws_that_only_laws_yml_declares
    context = Master::Fix::VisualUsability.context

    %w[DENSITY PROXIMITY LINEARITY ABSTRACTION SINGULARITY].each do |id|
      assert_match(/^#{id}: \S/, context)
    end
  end

  def test_baseline_guidance_covers_new_features_and_keeps_accessibility_separate
    law = Law.definitions.fetch(:BASELINE_COMPATIBILITY)

    ["field-sizing", "contrast-color()", "Trusted Types", "Navigation API"].each do |feature|
      assert_includes law.fix, feature
    end
    assert_includes law.fix, "feature detection"
    assert_includes law.fix, "keyboard"
    assert_includes law.fix, "not proof of accessibility or security"
  end

  def test_core_web_vitals_guidance_uses_current_field_thresholds
    law = Law.definitions.fetch(:CORE_WEB_VITALS)

    %w[LCP INP CLS].each { |metric| assert_includes law.ask, metric }
    %w[2.5 200 0.1 75th percentile].each { |threshold| assert_includes "#{law.ask} #{law.fix}", threshold }
    assert_includes law.fix, "field data"
  end

  def test_web_defaults_prefer_native_features_and_safe_fallbacks
    # The Law text wraps at heredoc line breaks; a phrase may span one.
    platform = Law.definitions.fetch(:WEB_PLATFORM_DEFAULTS).fix.split.join(" ")
    ["Baseline Widely available", "@supports", "feature detection", "Modern Web Guidance", "network access"]
      .each { |phrase| assert_includes platform, phrase }

    mobile = Law.definitions.fetch(:MOBILE_ACCESSIBILITY_DEFAULTS)
    %w[320 24 44 prefers-reduced-motion].each do |expectation|
      assert_includes "#{mobile.ask} #{mobile.fix}", expectation
    end
    assert_includes mobile.fix, "unobscured"

    pwa = Law.definitions.fetch(:PWA_RESILIENCE_DEFAULTS)
    %w[GET network-first cache-first same-origin idempotent].each do |expectation|
      assert_includes pwa.fix, expectation
    end
    assert_includes pwa.fix, "personalized responses"
  end
end
