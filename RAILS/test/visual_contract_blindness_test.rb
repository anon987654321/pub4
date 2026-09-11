# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../gates/visual_contract"

# visual_contract is the one gate in this tree that cannot be wrong about the
# pixels and can be wrong about everything else: it captures a screenshot per
# cell, and a cell that fetched the wrong page still produces a screenshot.
#
# Two blindnesses, and both were measured from the committed manifests rather
# than reasoned about. bsdports carried one screenshot SHA across all eight of
# its states and amber across eight of its ten, because a vertical lives on a
# subdomain a 127.0.0.1 crawl cannot reach — one live row covering for seventeen
# dead ones, with every accessibility and drift number that page counted
# eighteen times.
#
# The third state is the other half. Without --capture this gate navigates
# nothing, and it said "ok" under a runner line announcing that Chrome was
# present and the gate could measure.
class VisualContractBlindnessTest < Minitest::Test
  GATE = File.expand_path("../gates/visual_contract.rb", __dir__)
  RUNNER = File.expand_path("../gates/runner.rb", __dir__)

  def cell(state:, route:, sha:, viewport: :mobile)
    { app: :bsdports, state: state, viewport: viewport, route: route, status: 200,
      screenshot_sha256: sha, accessibility_violations: [], console_errors: [] }
  end

  # The defect: two different routes, one image. Whatever either cell claims to
  # have measured, it measured the other's page or neither's.
  def test_two_routes_that_captured_one_image_are_reported_as_blind_cells
    blind = VisualContractGate.identical_captures([
      cell(state: :public, route: "/", sha: "a" * 64),
      cell(state: :results, route: "/ports?q=git", sha: "a" * 64),
    ])

    assert_equal 1, blind.size
    states = blind.values.flatten.map { |row| row[:state] }

    assert_equal %i[public results], states.sort
  end

  # Remove the defect: each route its own page, and the gate reports nothing.
  def test_routes_that_each_captured_their_own_page_are_not_reported
    assert_empty VisualContractGate.identical_captures([
      cell(state: :public, route: "/", sha: "a" * 64),
      cell(state: :results, route: "/ports?q=git", sha: "b" * 64),
    ])
  end

  # The matrix doing its job: one route at two widths is two cells and, on a
  # page that does not reflow, can legitimately be one image per viewport. The
  # grouping is per viewport, so this must not fire.
  def test_the_same_route_at_two_viewports_is_not_a_blind_cell
    assert_empty VisualContractGate.identical_captures([
      cell(state: :public, route: "/", sha: "a" * 64, viewport: :mobile),
      cell(state: :public, route: "/", sha: "a" * 64, viewport: :desktop),
    ])
  end

  # bsdports declares detail, advisory and dependency as three lenses on one
  # document. That is deliberate, so it is a warning and not a finding — but
  # their counts are that page measured three times, which is worth saying.
  def test_three_lenses_on_one_document_are_a_warning_rather_than_a_blind_cell
    rows = [
      cell(state: :detail, route: "/ports/1", sha: "c" * 64),
      cell(state: :advisory, route: "/ports/1#cves-security-advisories", sha: "c" * 64),
      cell(state: :dependency, route: "/ports/1#this-package-requires", sha: "c" * 64),
    ]

    assert_empty VisualContractGate.identical_captures(rows)
    assert_equal 1, VisualContractGate.fragment_only_captures(rows).size
  end

  def test_distinct_documents_ignores_everything_after_the_fragment
    rows = [cell(state: :detail, route: "/ports/1", sha: "c" * 64),
            cell(state: :advisory, route: "/ports/1#cves", sha: "c" * 64)]

    assert_equal 1, VisualContractGate.distinct_documents(rows)
  end

  # THE assertion for this gate. A default run captures nothing; it may not
  # report that as a pass.
  def test_a_run_that_captures_nothing_exits_inconclusive_rather_than_ok
    out, status = Open3.capture2e(RbConfig.ruby, GATE)

    assert_equal 3, status.exitstatus, out
    assert_includes out, "nothing measured, so nothing is claimed"
  end

  def with_routes(routes)
    original = VisualContractGate::ROUTES
    VisualContractGate.send(:remove_const, :ROUTES)
    VisualContractGate.const_set(:ROUTES, routes.freeze)
    yield
  ensure
    VisualContractGate.send(:remove_const, :ROUTES)
    VisualContractGate.const_set(:ROUTES, original)
  end

  # A malformed matrix is still a verdict about the tree, and still blocks.
  # Exit 3 for "captured nothing" must not have swallowed the check that runs
  # on every invocation.
  def test_a_matrix_missing_its_failure_states_still_raises
    error = assert_raises(RuntimeError) do
      with_routes(brgen: { public: "/", sign_in: "/session/new" }) { VisualContractGate.validate! }
    end

    assert_match(%r{empty/error/offline}, error.message)
  end

  def test_a_matrix_that_declares_every_failure_state_validates
    with_routes(brgen: { public: "/", empty: "/?q=x", error: "/404", offline: "/offline" }) do
      assert_equal 12, VisualContractGate.validate!.length
    end
  end

  # The runner is where the exit code becomes a word people read. 3 must reach
  # the summary as INCONCLUSIVE and must not be added to the pass count.
  def test_the_runner_reports_the_uncaptured_run_as_inconclusive
    Dir.mktmpdir("visual-contract-runner") do |dir|
      out, status = Open3.capture2e(
        { "GATE_LEDGER" => File.join(dir, "ledger.jsonl") },
        RbConfig.ruby, RUNNER, "visual_contract"
      )

      assert_includes out, "visual_contract INCONCLUSIVE (checked nothing)"
      refute_includes out, "ALL SELECTED GATES PASSED"
      assert_equal 0, status.exitstatus, "an unmeasured gate must not block a run:\n#{out}"
    end
  end
end
