# frozen_string_literal: true

require "minitest/autorun"
require_relative "../gates/lib/rendered_suite"
require_relative "../gates/lib/layout_suite"

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
end
