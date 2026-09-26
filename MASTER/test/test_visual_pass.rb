# frozen_string_literal: true

require_relative "test_helper"
require File.expand_path("../../MASTER/gates/support/geometry_probe", __dir__)

# VisualPass measures through GeometryProbe and CompositionProbe, judges through
# the Council's :ui critique, and only turns a pick into a finding when it can
# name a surface, a viewport and a place in source. Each test drives one of
# those seams with the browser and the model replaced.
class VisualPassContractTest < Minitest::Test
  Pass = Master::Fix::VisualPass
  Probe = Deploy::GeometryProbe

  # Answers the expressions CompositionProbe sends, by what they ask.
  class ScriptedCdp
    attr_reader :expressions, :shots

    def initialize(url:, candidates:, editable: false, discovery: nil)
      @url = url
      @candidates = candidates
      @editable = editable
      @discovery = discovery
      @expressions = []
      @shots = []
      @signature = 0
    end

    def navigate(_url) = nil
    def screenshot(path, **) = @shots << path

    def evaluate(js)
      @expressions << js
      return @discovery || JSON.generate(@candidates) if js.include?("querySelectorAll(\"button, summary")
      return @editable if js.include?("field.focus()")
      return JSON.generate({ "n" => (@signature += 1) }) if js.include?("JSON.stringify({")
      return @url if js == "location.href"

      true
    end
  end

  def surface(app: "master", label: "chat", viewport: "mobile")
    Probe::Surface.new(app:, label:, path: "/", viewport:, port: 4000, width: 390, height: 844)
  end

  def with_tmp
    Dir.mktmpdir("visual-pass") { |dir| yield dir }
  end

  def test_visual_pass_uses_the_existing_rendered_measurement_stack
    with_tmp do |dir|
      pass = Pass.new(agent: Object.new, root: dir)
      pass.instance_variable_set(:@dir, dir)
      ghosts = Object.new
      def ghosts.capture(*, **) = { ghost: nil }
      pass.instance_variable_set(:@ghost_stack, ghosts)
      limits = []
      captured = Probe.stub(:with_browser, ->(**, &blk) { blk.call(Object.new.tap { |c| def c.screenshot(*, **) = nil }) }) do
        Probe.stub(:walk, { "elements" => [] }) do
          Probe.stub(:ok?, true) do
            Deploy::CompositionProbe.stub(:capture, ->(_cdp, _s, dir:, pass:, limit:) { limits << limit; [] }) do
              Deploy::MobileJourneyProbe.stub(:run, []) do
                Deploy::WebPlatformProbe.stub(:run, {}) { pass.send(:capture_surfaces, [surface], pass: 1) }
              end
            end
          end
        end
      end

      assert_equal [Pass::MAX_COMPOSITION_STATES], limits
      assert_equal "resting", captured.first.dig(:payload, "composition", "state")
      assert_equal({ ghost: nil }, captured.first[:visual_evidence])
    end
    refute defined?(::Selenium::WebDriver), "the visual pass drives CDP through GeometryProbe, not Selenium"
  end

  def test_visual_findings_enter_the_existing_ui_council_and_fix_protocol
    with_tmp do |dir|
      pass = Pass.new(agent: :agent, root: dir)
      pass.instance_variable_set(:@dir, dir)
      capture = { surface:, payload: { "elements" => [] }, screenshot: "x.png", journeys: [], platform: {} }
      pass.send(:decorate_design, [capture])
      assert capture[:payload].key?("design_fingerprint"), "every capture carries its design fingerprint"

      kwargs = nil
      critique = Struct.new(:run).new(:ran)
      sheet = Object.new
      def sheet.render(_) = "/tmp/sheet.png"
      # The usability laws are stubbed: this test is about the hand-off to the
      # Council, and VisualUsability.context has its own reader to prove.
      Master::Fix::VisualUsability.stub(:context, "USABILITY LAWS") do
        Master::Fix::VisualContactSheet.stub(:new, sheet) do
          Master::Review::Council::Critique.stub(:new, ->(**kw) { kwargs = kw; critique }) do
            pass.send(:run_critique, [capture], ["a.css"], {}, graph: nil)
          end
        end
      end

      assert_equal :ui, kwargs[:mode]
      assert_equal :agent, kwargs[:agent]
      assert_equal "/tmp/sheet.png", kwargs.dig(:visual_image, :path)
      assert_includes kwargs[:visual_context], Master::Design::VisualLanguage.context([capture]).lines.first.strip
      assert_includes kwargs[:visual_context], "HOSTILE VISUAL AUDIT"
      assert_includes kwargs[:visual_context], "USABILITY LAWS"
    end
    assert Probe.surfaces.any? { |s| s.app == "master" }, "MASTER's own face is a declared surface"
  end

  def test_visual_targets_are_limited_to_web_surfaces
    root = File.expand_path("..", Master::ROOT)
    pass = Pass.new(agent: Object.new, root:)

    assert pass.applicable?(File.join(root, "RAILS"))
    assert pass.applicable?(File.join(root, "RAILS/brgen/app"))
    assert pass.applicable?(File.join(root, "MASTER/web"))
    refute pass.applicable?(File.join(root, "MASTER/lib"))
    refute pass.applicable?(File.join(root, "STUDIO"))
    refute pass.applicable?(File.join(root, "RAILSX"))
  end

  def test_surface_selection_is_application_agnostic
    rows = [surface(app: "zeta", viewport: "desktop"), surface(app: "zeta"), surface(app: "master")]
    pass = Pass.new(agent: Object.new, root: File.expand_path("..", Master::ROOT))
    picked = Probe.stub(:surfaces, rows) { pass.send(:selected_surfaces, target: "RAILS", pass: 1) }

    assert_equal %w[zeta/chat/mobile zeta/chat/desktop], picked.map(&:id)
  end

  def test_composition_probe_clicks_safe_controls_and_measures_the_state
    measured = []
    cdp = ScriptedCdp.new(url: surface.url, editable: "search",
                          candidates: [{ "selector" => "body > button:nth-of-type(1)", "label" => "Menu", "stateful" => false }])
    captures = with_tmp do |dir|
      Probe.stub(:measure_current, ->(_cdp, s) { measured << s.label; { "elements" => [] } }) do
        Probe.stub(:ok?, true) do
          Deploy::WebPlatformProbe.stub(:run, {}) { Deploy::CompositionProbe.capture(cdp, surface, dir:, pass: 1) }
        end
      end
    end
    discovery = cdp.expressions.find { |js| js.include?("querySelectorAll(") && js.include?("stateful") }
    typed = cdp.expressions.find { |js| js.include?("field.focus()") }

    assert_includes discovery, %(querySelectorAll("button, summary, [role='button']"))
    assert_includes discovery, "data-master-composition-ignore"
    assert_includes typed, "MASTER visual probe"
    assert_equal %w[chat__interaction_1 chat__interaction_1__input], measured
    assert_equal %w[interaction interaction_input], captures.map { |c| c.dig(:payload, "composition", "state") }
    assert_equal Integer(ENV.fetch("MASTER_VISUAL_COMPOSITION_PAIRS", "4")), Deploy::CompositionProbe::MAX_PAIRS
  end

  def test_composition_probe_fails_closed_on_bad_discovery
    cdp = ScriptedCdp.new(url: surface.url, candidates: [], discovery: "not json")
    error = with_tmp do |dir|
      assert_raises(RuntimeError) { Deploy::CompositionProbe.capture(cdp, surface, dir:, pass: 1) }
    end

    assert_match(/composition discovery returned invalid JSON/, error.message)
  end

  def test_visual_findings_must_be_addressable
    with_tmp do |dir|
      css = File.join(dir, "a.css")
      File.write(css, "x\n.hero { }\n")
      html = File.join(dir, "a.html")
      File.write(html, "<p>\nWelcome home\n</p>\n")
      law = Master::Fix::VisualUsability.ids.first
      pass = Pass.new(agent: Object.new, root: dir)
      find = ->(pick) { pass.send(:finding_for, pick, [css, html], { ".hero" => css }) }

      by_selector = find.("surface: master/chat/mobile viewport: mobile .hero laws: #{law}")
      assert_equal [Pass::RULE_ID, css, 2], [by_selector[:rule], by_selector[:file], by_selector[:line]]
      by_text = find.(%(surface: master/chat/mobile viewport: mobile text anchor: "Welcome home" laws: #{law}))
      assert_equal [html, 2], [by_text[:file], by_text[:line]]
      assert_nil find.("viewport: mobile .hero laws: #{law}"), "no surface, no finding"
      assert_nil find.("surface: master/chat/mobile .hero laws: #{law}"), "no viewport, no finding"
      assert_nil find.("surface: master/chat/mobile viewport: mobile laws: #{law}"), "no anchor, no finding"
    end
  end

  # /fix constructs the pass with MASTER's own directory as root; RAILS must
  # still read as RAILS, or the whole rendered review silently skips.
  def test_rails_is_a_visual_target_when_root_is_master
    pass = Master::Fix::VisualPass.new(agent: Object.new, root: Master::ROOT)
    rails = File.expand_path("../RAILS", Master::ROOT)

    assert pass.applicable?(rails)
    assert_equal File.expand_path("..", Master::ROOT), pass.send(:repo_root)
  end
end
