# frozen_string_literal: true

require "minitest/autorun"
require_relative "../gates/lib/rendered_suite"
require_relative "../gates/lib/layout_suite"
require_relative "../lib/fix/reachability"
require_relative "../lib/trace/dmesg"

class TestGateCoverageReporting < Minitest::Test
  def test_rendered_composite_names_each_leaf_verdict_and_measurement_count
    leaf = Deploy::GateResult.new.checked!(7)
    leaf.warn("geometry: measured seven cells")

    line = Deploy::RenderedSuiteGate.new.coverage_line("RenderedGeometryGate", leaf)

    assert_match(/coverage0: rendered\/RenderedGeometryGate PASSED/, line)
    assert_includes line, "7 check(s)"
  end

  def test_layout_composite_reports_failures_and_errors_as_counts
    leaf = Deploy::GateResult.new
    leaf.fail("CSS contract broken")
    leaf.errored!("probe crashed")

    line = Deploy::LayoutSuiteGate.new.coverage_line("CssConstitutionGate", leaf)

    assert_match(/coverage0: layout\/CssConstitutionGate FAILED/, line)
    assert_includes line, "1 failure(s)"
    assert_includes line, "1 error(s)"
  end

  def test_layout_suite_promotes_inconclusive_rendered_evidence_to_a_failure
    suite = Deploy::LayoutSuiteGate.new
    aggregate = Deploy::GateResult.new
    rendered = Deploy::GateResult.new.inconclusive!("no Chrome")

    suite.require_rendered_evidence!(aggregate, rendered)

    refute aggregate.ok?
    assert_match(/rendered evidence is incomplete/, aggregate.failures.first)
    assert_match(/no Chrome/, aggregate.failures.first)
  end

  def test_layout_suite_promotes_soft_visual_findings_to_a_failure
    suite = Deploy::LayoutSuiteGate.new
    aggregate = Deploy::GateResult.new
    rendered = Deploy::GateResult.new.checked!
    rendered.fail("visual baseline missing", severity: :soft)

    suite.require_rendered_evidence!(aggregate, rendered)

    refute aggregate.ok?
    assert_match(/unapproved visual finding/, aggregate.failures.first)
  end

  def test_reachability_sweep_reports_failure_details_and_counts_omitted_warnings
    reachability = Master::Fix::Reachability.allocate
    coverage = ["coverage0: layout/CssConstitutionGate FAILED — 4 check(s), 2 failure(s)"]
    failures = Array.new(3) { |i| "fixture failure #{i}" }
    actionable = ["css_constitution type_scale: brgen/app.scss:17 15px"]
    warnings = coverage + actionable + Array.new(26) { |i| "fixture warning #{i}" }
    result = Struct.new(:warnings, :failures, :unchecked, :errors).new(warnings, failures, ["missing Chrome"], [])

    lines = []
    Master::Trace::Dmesg.stub(:status, ->(unit, message, **) { lines << [unit, message] }) do
      reachability.send(:report_layout_diagnostics!, result)
    end

    assert_includes lines, ["layout0", coverage.first]
    assert_includes lines, ["layout0", "failure: fixture failure 0"]
    assert_includes lines, ["layout0", "unchecked: missing Chrome"]
    assert_includes lines, ["layout0", actionable.first]
    assert_includes lines, ["layout0", "warning: 2 additional item(s) omitted"]
  end
end
