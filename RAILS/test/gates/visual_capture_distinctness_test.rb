# frozen_string_literal: true

require "minitest/autorun"
require "json"

# A visual crawl can navigate every cell and still measure nothing.
#
# `grade` decides whether a cell failed and `measured.zero?` decides whether
# anything navigated at all. Between them sat the case the committed manifests
# were actually in: eighteen declared states across three apps that had all
# fetched one of three pages.
#
#   bsdports  screenshot SHA cc28fcad for all eight states
#   amber     screenshot SHA 77355941 for eight of ten
#   brgen     marketplace -> "/", marketplace_sign_in -> "/session/new"
#             (a vertical lives on a subdomain; the crawl reaches the app by
#             port on 127.0.0.1, so the lens landed on the apex)
#
# Every accessibility count and drift ratio in those manifests is therefore one
# page counted many times, and the gate exited 0. This pins the check that says
# so, including on the real manifests if they are ever recaptured that way.
class VisualCaptureDistinctnessTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # Loaded rather than required: visual_contract.rb runs a crawl at the bottom
  # of the file, so requiring it would launch one. Evaluated once at load, not
  # per test, or every constant in the module re-initialises on each run.
  GATE = begin
    source = File.read(File.join(ROOT, "gates/visual_contract.rb"))
    body = source[/module VisualContractGate.*?\nend\n/m] or raise "gate module not found"
    TOPLEVEL_BINDING.eval(body) # rubocop:disable Security/Eval
    ::VisualContractGate
  end

  def gate = GATE

  def row(state:, route:, sha:, viewport: "desktop")
    { app: "brgen", state:, route:, viewport:, screenshot_sha256: sha, status: 200 }
  end

  def test_two_routes_returning_one_image_is_reported
    results = [
      row(state: "public", route: "/", sha: "a" * 64),
      row(state: "marketplace", route: "/markedsplass", sha: "a" * 64),
    ]

    duplicates = gate.identical_captures(results)

    assert_equal 1, duplicates.length
    states = duplicates.values.first.map { |r| r[:state] }
    assert_equal %w[public marketplace], states
  end

  def test_the_same_route_at_two_viewports_is_not_a_duplicate
    results = [
      row(state: "public", route: "/", sha: "a" * 64, viewport: "desktop"),
      row(state: "public", route: "/", sha: "a" * 64, viewport: "mobile"),
    ]

    assert_empty gate.identical_captures(results),
                 "one route at two widths is the matrix working, not a blind cell"
  end

  def test_distinct_pages_are_clean
    results = [
      row(state: "public", route: "/", sha: "a" * 64),
      row(state: "results", route: "/?sort=latest", sha: "b" * 64),
    ]

    assert_empty gate.identical_captures(results)
  end

  # Rows that never navigated carry no SHA; measured.zero? owns that case and
  # this check must not double-report it.
  def test_rows_without_a_screenshot_are_left_alone
    results = [
      row(state: "public", route: "/", sha: nil),
      row(state: "empty", route: "/?q=none", sha: nil),
    ]

    assert_empty gate.identical_captures(results)
  end

# Routes that differ only after the "#" are one document, and one document
# screenshots to one set of bytes. bsdports declares detail, advisory and
# dependency that way against /ports/1 — deliberate, and the first version of
# this check failed the whole capture on it.
def test_fragment_only_routes_are_not_a_blind_cell
  results = [
    row(state: "detail", route: "/ports/1", sha: "d" * 64),
    row(state: "advisory", route: "/ports/1#cves-security-advisories", sha: "d" * 64),
    row(state: "dependency", route: "/ports/1#this-package-requires", sha: "d" * 64),
  ]

  assert_empty gate.identical_captures(results),
               "a fragment moves the viewport, not the page"
end

# Reported all the same: those three states contribute one measurement between
# them, so every count they produce is that page counted three times.
def test_fragment_only_routes_are_still_reported
  results = [
    row(state: "detail", route: "/ports/1", sha: "d" * 64),
    row(state: "advisory", route: "/ports/1#cves", sha: "d" * 64),
  ]

  assert_equal 1, gate.fragment_only_captures(results).length
end

# A real blind cell hiding among fragment siblings must still fail.
def test_a_different_path_among_fragments_still_fails
  results = [
    row(state: "detail", route: "/ports/1", sha: "d" * 64),
    row(state: "advisory", route: "/ports/1#cves", sha: "d" * 64),
    row(state: "results", route: "/ports?q=git", sha: "d" * 64),
  ]

  assert_equal 1, gate.identical_captures(results).length
end

  # The historical shape, from bsdports-manifest.json as committed: eight states,
  # one image. If a recapture ever produces this again the gate now fails on it.
  def test_the_bsdports_shape_is_caught
    states = %w[public empty results detail advisory dependency error offline]
    routes = %w[/ /ports?q=x /ports?q=git /ports/1 /ports/1#cves /ports/1#deps /404 /offline]
    results = states.zip(routes).map { |state, route| row(state:, route:, sha: "cc28fcad" * 8) }

    duplicates = gate.identical_captures(results)

    assert_equal 1, duplicates.length
    assert_equal 8, duplicates.values.first.length
  end
end
