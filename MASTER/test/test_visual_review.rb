# frozen_string_literal: true

require_relative "test_helper"
require File.expand_path("../../MASTER/gates/support/geometry_probe", __dir__)
require "operator/visual_review"
require "fix/visual_pass_review_entry"

# The review drives VisualPass's steps one at a time. These tests replace the
# browser, the triangle and the council with stand-ins and check what the
# command promises: arguments, the folder it leaves, exit codes, and that it
# stops only the apps it started.
class VisualReviewTest < Minitest::Test
  Probe = Deploy::GeometryProbe
  Surf = Probe::Surface

  class FakeGraph
    def errors = []
  end

  class FakeSession
    attr_reader :opened, :critiqued

    def initialize(surfaces, dir_images:, critique: nil, miss: [])
      @surfaces = surfaces
      @miss = miss
      @critique = critique
      @images = dir_images
    end

    def review_surfaces(target:) = @surfaces
    def review_open(dir:, ghost_root:) = (@dir = dir; @opened = dir; FileUtils.mkdir_p(dir))
    def review_graph = FakeGraph.new
    def review_decorate(_captures) = nil
    def review_sheet(_captures) = File.join(@dir, "rendered-ui-contact-sheet.png").tap { |p| File.write(p, "png") }
    def review_sources(target:, captures:, graph:) = [["/x/app.css"], { ".a" => "/x/app.css" }]

    def review_capture(surfaces)
      surfaces.reject { |s| @miss.include?(s.id) }.map do |s|
        shot = File.join(@dir, "#{s.id.gsub("/", "_")}.png")
        File.write(shot, "png")
        { surface: s, screenshot: shot, journeys: [],
          payload: { "composition" => { "state" => "resting" }, "elements" => [], "vw" => 390, "vh" => 844 } }
      end
    end

    def review_critique(*_args, graph:)
      @critiqued = true
      [@critique, nil]
    end

    def review_pick(pick, _sources, _anchors) = pick.include?("anchored") ? { file: "/x/app.css", line: 3 } : nil
  end

  class FakeTriangle
    attr_reader :released

    def initialize(down: [])
      @down = down
      @released = false
    end

    def ensure_up(_apps) = @down
    def release = (@released = true; [])
  end

  def surface(app: "brgen", label: "core", viewport: "mobile")
    Surf.new(app:, label:, path: "/", viewport:, port: 3000, width: 390, height: 844)
  end

  def run_review(argv, session:, triangle: FakeTriangle.new, probe: -> { true })
    Dir.mktmpdir("visual-review") do |root|
      out = File.join(root, "out")
      io = StringIO.new
      code = Operator::VisualReview.main(argv + ["--no-open", "--out", out], root:, session:, triangle:, probe:, io:)
      yield code, out, io.string if block_given?
      code
    end
  end

  def test_parse_defaults_and_flags
    opts = Operator::VisualReview.parse(%w[--app brgen,amber --surface core --no-critique --no-open], root: "/r", now: Time.utc(2026, 1, 2, 3, 4, 5))
    assert_equal %w[brgen amber], opts.apps
    assert_equal %w[core], opts.surfaces
    refute opts.critique
    refute opts.open
    assert_equal "/r/MASTER/.master/visual_review/20260102T030405", opts.out
  end

  def test_parse_refuses_other_trees_engines_and_unknown_flags
    assert_raises(Operator::VisualReview::Failure) { Operator::VisualReview.parse(%w[--tree OPENBSD], root: "/r") }
    assert_raises(Operator::VisualReview::Failure) { Operator::VisualReview.parse(%w[--engines firefox], root: "/r") }
    assert_raises(Operator::VisualReview::Failure) { Operator::VisualReview.parse(%w[--bogus], root: "/r") }
  end

  def test_no_critique_writes_folder_and_never_calls_the_council
    session = FakeSession.new([surface, surface(app: "amber")], dir_images: nil)
    run_review(%w[--no-critique], session:) do |code, out, printed|
      assert_equal 0, code
      refute session.critiqued
      html = File.read(File.join(out, "index.html"))
      assert_includes html, "captured 2/2 declared surfaces"
      assert_includes html, "Skipped, --no-critique"
      assert_includes html, "brgen_core_mobile.png"
      assert_includes printed, out
    end
  end

  def test_missed_surfaces_are_listed_and_counted
    a = surface
    b = surface(app: "amber")
    session = FakeSession.new([a, b], dir_images: nil, miss: [b.id])
    run_review(%w[--no-critique], session:) do |code, out, _|
      assert_equal 0, code
      html = File.read(File.join(out, "index.html"))
      assert_includes html, "captured 1/2 declared surfaces"
      assert_includes html, "Declared but not captured"
      assert_includes html, b.id
    end
  end

  def test_critique_picks_show_anchor_status_and_exit_one
    result = Master::Result.ok({ feedback: "full text <b>", cherry_picks: ["anchored pick", "loose pick"] })
    session = FakeSession.new([surface], dir_images: nil, critique: result)
    run_review([], session:) do |code, out, _|
      assert_equal 1, code
      html = File.read(File.join(out, "index.html"))
      assert_includes html, "anchored /x/app.css:3"
      assert_includes html, "unanchored"
      assert_includes html, "full text &lt;b&gt;"
    end
  end

  def test_triangle_down_is_exit_two_and_still_releases
    triangle = FakeTriangle.new(down: ["brgen"])
    session = FakeSession.new([surface], dir_images: nil)
    code = run_review(%w[--no-critique], session:, triangle:)
    assert_equal 2, code
    assert triangle.released
    assert_nil session.opened
  end

  def test_chrome_missing_is_exit_two
    session = FakeSession.new([surface], dir_images: nil)
    assert_equal 2, run_review(%w[--no-critique], session:, probe: -> { false })
  end

  def test_no_matching_surface_is_exit_two
    session = FakeSession.new([surface], dir_images: nil)
    assert_equal 2, run_review(%w[--no-critique --app amber], session:)
  end

  def test_triangle_owner_stops_only_what_it_started
    calls = []
    up = { 3000 => true, 3001 => false }
    owner = Operator::VisualReviewTriangle.new(
      ports: { "brgen" => 3000, "amber" => 3001 },
      runner: ->(args) { calls << args; up[3001] = true if args.first == "up"; ["", true] },
      probe: ->(port) { up[port] },
    )
    assert_empty owner.ensure_up(%w[brgen amber])
    assert_equal [%w[up amber]], calls
    assert_equal %w[amber], owner.release
    assert_equal [%w[up amber], %w[down amber]], calls
    assert_empty owner.release
  end

  def test_triangle_owner_starts_nothing_when_everything_answers
    calls = []
    owner = Operator::VisualReviewTriangle.new(ports: { "brgen" => 3000 }, runner: ->(a) { calls << a; ["", true] }, probe: ->(_) { true })
    assert_empty owner.ensure_up(%w[brgen])
    assert_empty owner.release
    assert_empty calls
  end

  def test_page_escapes_and_is_self_contained
    html = Operator::VisualReviewPage.render(generated_at: "now", summary: "s", coverage_line: "c", missing: [], rows: [{ title: "<x>", problems: ["a&b"], screenshot: "s.png" }], notes: [])
    assert_includes html, "&lt;x&gt;"
    assert_includes html, "a&amp;b"
    refute_match(%r{https?://}, html)
    assert_includes html, "prefers-color-scheme: dark"
  end
end
