# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require File.expand_path("../../MASTER/gates/support/geometry_probe", __dir__)
require File.expand_path("../../MASTER/gates/visual_contract", __dir__)

# The rendered half of /fix: the geometry walk Chrome runs, the screenshot
# contract that shares its browser, the anchors a visual finding must carry, and
# the council's issue numbering. Each is exercised, with Chrome replaced where
# the question is about what the Ruby does with a browser rather than the page.
class TestRenderedVisualConvergence < Minitest::Test
  REPO = File.expand_path("../..", __dir__)

  # Replaces a singleton method for the block and puts the original back.
  def swap(owner, name, impl)
    original = owner.method(name)
    owner.define_singleton_method(name, impl)
    yield
  ensure
    owner.define_singleton_method(name, original)
  end

  # Only walk.js and the accessibility probe need a page, so they share one
  # browser. d7e92d999 made the walk report what the council reads: the first
  # screen's blocks, actions and area ratios, and the typography scale. The
  # ch-measure mislabel stays gone.
  def test_geometry_walk_and_accessibility_probe_run_in_chrome
    skip "no Chrome/Chromium on this machine" unless Deploy::CdpSession.available?

    Dir.mktmpdir do |dir|
      page = File.join(dir, "page.html")
      File.write(page, <<~HTML)
        <!doctype html><html lang="en"><head><title>walk</title></head><body><main>
        <h1 style="font-size:40px">Heading</h1><h2 style="font-size:24px">Sub</h2>
        <section style="height:400px"><p>Body text that is long enough to read.</p>
        <a href="/next">Next</a><button>Act</button><img src="missing.png"></section>
        </main></body></html>
      HTML
      walk = nil
      a11y = nil
      Deploy::CdpSession.open do |cdp|
        cdp.viewport(390, 844, mobile: true)
        cdp.navigate("file://#{page}")
        walk = cdp.evaluate(Deploy::GeometryProbe::WALK)
        # An expression, not a Selenium script body: a leading `return` would
        # be a SyntaxError here.
        a11y = cdp.evaluate(VisualContractGate::ACCESSIBILITY_PROBE)
      end

      first = walk.dig("visual", "first_screen")
      assert_operator first["largest_element_area_ratio"], :>, 0
      assert_includes first["primary_candidates"].map { |c| c["tag"].to_s.downcase }, "button"
      assert_includes walk.dig("visual", "typography", "heading_sizes").map { |h| [h["tag"], h["px"].to_i] }, ["h1", 40]
      assert_includes walk.dig("visual", "typography", "distinct_font_sizes").map(&:to_i), 24
      refute_includes JSON.generate(walk), "text_measures_ch_approx"
      assert_equal ["image_without_alt"], a11y
    end
  end

  # A CDP double for the capture loop: every call is logged, and a screenshot
  # writes distinct bytes so each cell has its own SHA.
  class RecordingCdp
    attr_reader :calls

    def initialize = @calls = []
    def viewport(*) = @calls << :viewport
    def headers(*) = @calls << :headers
    def clear_cookies = @calls << :clear_cookies
    def clear_events = @calls << :clear_events
    def navigate(url) = @calls << [:navigate, url]
    def screenshot(path, **) = File.write(path, "png #{@calls.length}")
    def status = 200
    def console_errors = []

    def evaluate(js) = js == "document.title" ? "title" : []
  end

  # 4ee2da222 moved capture onto the geometry probe's browser: one CDP session,
  # no subprocess, no Selenium, and console evidence reset before each page so
  # one cell's errors are not billed to the next.
  def test_visual_contract_captures_in_the_geometry_probe_browser
    cdp = RecordingCdp.new
    opened = []
    browser = ->(root:, warm:, &block) { opened << [root, warm]; block.call(cdp) }
    no_process = ->(*) { flunk "visual_contract started a subprocess" }

    results = Dir.mktmpdir do |dir|
      swap(Deploy::GeometryProbe, :with_browser, browser) do
        swap(Open3, :capture3, no_process) do
          swap(Process, :spawn, no_process) do
            VisualContractGate.capture(base: "http://127.0.0.1:1", app: "bsdports", output: dir)
          end
        end
      end
    end

    assert_equal [[REPO, []]], opened, "one browser, rooted at the repo, warming nothing"
    assert_equal VisualContractGate.matrix("bsdports").length, results.length
    navigations = cdp.calls.each_index.select { |i| cdp.calls[i].is_a?(Array) }
    assert_equal results.length, navigations.length
    navigations.each { |i| assert_includes cdp.calls[(i - 4)...i], :clear_events }
    assert_nil defined?(Selenium), "the gate loaded Selenium"
  end

  def test_visual_contract_without_chrome_cannot_measure
    unavailable = ->(**) { raise Deploy::CdpSession::Unavailable, "no Chrome" }

    swap(Deploy::GeometryProbe, :with_browser, unavailable) do
      Dir.mktmpdir do |dir|
        assert_raises(VisualContractGate::CannotMeasure) do
          VisualContractGate.capture(base: "http://127.0.0.1:1", app: "brgen", output: dir)
        end
      end
    end
  end

  def test_cdp_console_evidence_can_be_reset_between_pages
    cdp = Deploy::CdpSession.new
    cdp.events << { "method" => "Runtime.consoleAPICalled" }

    cdp.clear_events

    assert_empty cdp.events
  end

  # A rendered finding must name its surface, its viewport and a place in
  # source; a pick that cannot is dropped rather than pinned to a guessed file.
  def test_rendered_repairs_require_a_stable_anchor
    law = Master::Fix::VisualUsability.ids.first
    Dir.mktmpdir do |dir|
      css = File.join(dir, "feed.css")
      File.write(css, "body {}\n.feed-card { margin: 0 }\n")
      pass = Master::Fix::VisualPass.new(agent: nil, root: dir)
      find = ->(pick, anchors = { ".feed-card" => css }) { pass.send(:finding_for, pick, [css], anchors) }

      finding = find.call("surface=brgen/feed viewport=mobile selector=.feed-card laws: #{law}")
      assert_equal [css, 2], finding.values_at(:file, :line)

      assert_nil find.call("viewport=mobile selector=.feed-card laws: #{law}"), "no surface"
      assert_nil find.call("surface=brgen/feed selector=.feed-card laws: #{law}"), "no viewport"
      assert_nil find.call("surface=brgen/feed viewport=mobile laws: #{law}"), "no selector or text"
    end
  end

  def test_visual_pass_cannot_guess_an_unanchored_source_file
    law = Master::Fix::VisualUsability.ids.first
    Dir.mktmpdir do |dir|
      css = File.join(dir, "feed.css")
      File.write(css, ".feed-card { margin: 0 }\n")
      pass = Master::Fix::VisualPass.new(agent: nil, root: dir)

      # The selector maps to no anchor and the text appears in no source: the
      # one candidate file is not taken as the answer.
      pick = %(surface=brgen/feed viewport=mobile selector=.orphan visible text="Nowhere" laws: #{law})
      assert_nil pass.send(:finding_for, pick, [css], {})

      pick = %(surface=brgen/feed viewport=mobile visible text="feed-card" laws: #{law})
      assert_equal [css, 1], pass.send(:finding_for, pick, [css], {}).values_at(:file, :line)
    end
  end

  def test_ui_critique_excludes_judge_from_issue_numbering
    critic = Master::Review::Council::Critique.new(mode: :ui, agent: nil, files: [])
    feedback = [
      { persona: "Typographer", feedback: "Body text is 13px on mobile.\nmore" },
      { persona: "Judge", feedback: "Verdict: two issues stand." },
      { persona: "Layout", feedback: "The feed card overflows at 390px." },
    ]

    prompt = critic.send(:ideation_prompt, feedback)

    assert_includes prompt, "1. Body text is 13px on mobile."
    assert_includes prompt, "2. The feed card overflows at 390px."
    refute_includes prompt, "Verdict"
    assert(Master::Review::Council::Critique::Modes::TABLE[:ui][:constraints].any? { |c| c.include?("state VISUAL_CLEAN explicitly") },
           "the ui panel must be able to say the render is clean")
  end
end
