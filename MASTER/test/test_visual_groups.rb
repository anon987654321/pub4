# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fix/visual_groups"
require "fix/visual_lane"
require "fix/tap_target_pad"

# Fixture sweeps: eight routes on two viewports, each reporting the same header warning,
# the same off-scale rhythm and the same crowded selector, plus one broken route.
module VisualSweepFixture
  BROWSER = "[RenderedSuiteCheck] [BrowserDiagnosticsCheck] browser_diagnostics:"
  GEOMETRY = "[RenderedSuiteCheck] [RenderedGeometryCheck]"
  COOP = "browser console error: other: The Cross-Origin-Opener-Policy header has been ignored, " \
         "because the URL's origin was untrustworthy.: http://%s/"

  SHEET = "RAILS/brgen/app/assets/stylesheets/_feed.scss"
  WIKI = "http://brgen.no/communities/30/wiki"
  VIEWPORTS = %w[mobile desktop].freeze
  ROUTES = %w[core marketplace dating tv maps messenger nearby search].freeze

  module_function

  def cell(route, viewport)
    id = "brgen/#{route}/#{viewport}"

    [
      "#{BROWSER} #{id} — #{format(COOP, "#{route}.brgen.no")}",
      "#{GEOMETRY} geometry rhythm: #{id} #{route.size}/40 rendered gaps (#{route.size * 2}%) off the 8px scale " \
      "— 12px×5, 6px×3 principle=rhythm",
      "#{GEOMETRY} geometry target_spacing: #{id} has 2 undersized target pair(s) closer than 24px " \
      "— a.feed-action (20x18) and a.feed-action (20x18) are 3.0px apart (principle=fitts)",
    ]
  end

  def broken(viewport)
    id = "brgen/communities_wiki/#{viewport}"
    ["#{BROWSER} #{id} — document returned HTTP 404",
     "#{BROWSER} #{id} — resource returned an error: HTTP 404 #{WIKI} (Document)"]
  end

  def lines
    cells = ROUTES.product(VIEWPORTS).flat_map { |route, viewport| cell(route, viewport) }
    sheet = [6, 10].map { |px| "[DesignMetricsCheck] design_metrics rhythm: #{SHEET} spacing #{px}px not in 8px scale" }
    cells + VIEWPORTS.flat_map { |viewport| broken(viewport) } + sheet +
      ["layout_suite: rendered evidence is incomplete — 3 unapproved visual finding(s)"]
  end

  def urls = VIEWPORTS.to_h { |viewport| ["brgen/communities_wiki/#{viewport}", WIKI] }

  def groups = Master::Fix::VisualGroups.build(lines, urls:)

  def cells = ROUTES.size * VIEWPORTS.size
end

# Many findings, few stable keys, what users meet first.
class TestVisualGroups < Minitest::Test
  Fixture = VisualSweepFixture

  def test_many_findings_collapse_to_one_group_per_cause
    groups = Fixture.groups

    assert_equal 55, Fixture.lines.size
    assert_equal 5, groups.size, groups.map(&:key).join("\n")
  end

  def test_one_header_warning_on_every_page_is_one_group
    coop = Fixture.groups.find { |group| group.runtime? && group.member_count == Fixture.cells }

    assert coop
    assert_equal Fixture.cells, coop.surfaces.size
  end

  def test_a_broken_route_is_one_group_whatever_line_reported_it
    route = Fixture.groups.find(&:locator)

    assert_equal "HTTP 404 brgen.no/communities/:id/wiki", route.locator
    assert_equal 4, route.member_count
  end

  def test_keys_name_the_selector_and_the_stylesheet
    groups = Fixture.groups
    crowded = groups.find { |group| group.selector == "a.feed-action" }

    assert_equal "RenderedGeometryCheck/geometry target_spacing", crowded.law
    assert_equal 2, groups.find { |group| group.file == Fixture::SHEET }.member_count
  end

  def test_keys_are_stable_across_sweeps_and_order
    first = Fixture.groups.map(&:id)
    again = Master::Fix::VisualGroups.build(Fixture.lines.reverse, urls: Fixture.urls).map(&:id)

    assert_equal first.sort, again.sort
    assert_equal first.uniq.size, first.size
  end

  def test_what_users_meet_comes_first
    impacts = Fixture.groups.map(&:impact)

    assert_equal %i[runtime runtime], impacts.first(2)
    assert_equal impacts.sort_by { |impact| impact == :runtime ? 0 : 1 }, impacts
  end

  def test_the_report_carries_what_a_review_page_needs
    report = Master::Fix::VisualGroups.report(Fixture.groups, lane: :visual, sweeps: { before: {}, after: nil })
    row = report.fetch("rows").first

    assert_equal 5, report.fetch("groups")
    assert_empty %w[id key law file selector members examples routes viewports fix before after] - row.keys
    assert_equal %w[mobile desktop], row.fetch("viewports")
  end

  def test_tap_target_pad_writes_the_repo_pattern
    rule = Master::Fix::TapTargetPad.rule("a.feed-action")

    assert_includes rule, "display: inline-block;"
    assert_includes rule, "padding-block: max(0px, (var(--tap-min) - 1lh) / 2);"
    assert_includes rule, "margin-block: min(0px, (1lh - var(--tap-min)) / 2);"
    refute_includes Master::Fix::TapTargetPad.rule(".feed-action"), "display:"
  end
end

# Mechanical fixers settle what they can; the model is asked once per remaining group, never
# for a baseline only the operator approves, and the resweep decides what is cleared.
class TestVisualLane < Minitest::Test
  Fixture = VisualSweepFixture
  Lane = Master::Fix::VisualLane

  def world(asked: [], resweeps: [], mechanical: true)
    after = Fixture.lines.grep_v(/feed-action|_feed\.scss/)
    shots = { "brgen/core/mobile" => "/tmp/c.png" }

    Lane::World.new(
      sweep: -> { { findings: Fixture.lines, urls: Fixture.urls, screenshots: shots } },
      resweep: -> { (resweeps << :resweep) && { findings: after, urls: Fixture.urls } },
      snap: ->(group) { group.file && mechanical ? :applied : nil },
      pad: ->(group) { Master::Fix::TapTargetPad.applicable?(group) && mechanical ? :applied : nil },
      repair: ->(group) { (asked << group.id) && :not_kept },
    )
  end

  def run_lane(world, **options)
    Dir.mktmpdir do |root|
      outcome = Lane.new(world:, repo_root: root, **options).run
      yield outcome, JSON.parse(File.read(outcome.report)).fetch("rows")
    end
  end

  def test_mechanical_fixers_go_first_and_the_model_gets_one_call_per_group_left
    asked = []
    run_lane(world(asked:)) do |outcome, rows|
      assert_equal 3, asked.size
      assert_equal 2, rows.count { |row| row.fetch("fix") == "mechanical" }
      assert_equal 2, outcome.cleared
    end
  end

  def test_the_report_lands_in_master_state_with_before_screenshots
    run_lane(world) do |outcome, rows|
      assert outcome.report.end_with?(File.join("MASTER", ".master", "visual_groups.json"))
      assert_equal ["/tmp/c.png"], rows.find { |row| row.fetch("before").any? }.fetch("before")
    end
  end

  def test_no_repair_means_no_resweep_and_nothing_called_cleared
    resweeps = []
    run_lane(world(resweeps:, mechanical: false), model_groups: 2) do |outcome, rows|
      assert_empty resweeps
      assert_equal [0, 5], [outcome.cleared, outcome.remaining]
      assert_equal 3, rows.count { |row| row.fetch("fix_detail").include?("model budget") }
    end
  end
end
