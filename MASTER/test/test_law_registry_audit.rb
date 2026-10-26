# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "review/scan/law_dsl"
require_relative "../lib/operator/law_reach"

class TestLawRegistryAudit < Minitest::Test
  # Defined here on purpose: Law.inherited registers every subclass in the
  # process, so this class is in the registry the moment this file loads. It is
  # the shape that made law_deps.ungraphed read 133 alone and 135 under
  # `rake test` — a census answering a different number depending on what else
  # the process had run.
  class LawDefinedByATest < Master::Review::Scan::Law
    def initialize
      super
      @id = "rule_defined_by_a_test"
    end

    def check(_code, path:) = []
  end

  def audit = Master::Review::Scan::LawRegistryAudit.new(root: Master::ROOT)

  def test_audit_declares_its_set_dependency_in_a_fresh_process
    lib = File.expand_path("../lib", __dir__)
    script = "require 'review/scan/law_registry_audit'; abort 'set unavailable' unless defined?(Set)"
    output, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script)

    assert status.success?, output
  end

  def test_audit_reports_yaml_and_registry_counts
    report = audit.call
    assert_operator report.yaml_laws, :>, 100
    assert_operator report.registry_ids.size, :>, 50
    assert_operator report.adherence_pct, :>, 20.0
  end

  # Adherence used to average registry coverage against a term that read
  # `(wired + unwired) / (wired + unwired)`, so it could not fall below 55 and
  # SelfTest's "below 35 is a violation" check could not fire. An empty registry
  # is the input that proves the floor is gone.
  def test_adherence_can_reach_zero
    empty = audit.call.with(mechanical: [])

    assert_in_delta 0.0, empty.adherence_pct
  end

  # Three check banners and lib/operator/law_reach.rb print a count of one population,
  # and they read 107 and 115 for as long as one of them subtracted rather than
  # counted. Both directions: the shared answer, and that it is not the
  # subtraction that used to stand in for it.
  def test_coverage_agrees_with_law_reach
    report = audit.call
    reach = Operator::LawReach.mechanical(Operator::LawReach.laws).size

    assert_equal reach, report.mechanical.size
    assert_includes report.coverage_line, "#{reach} of #{report.yaml_laws}"
    refute_equal report.yaml_laws - report.semantic_only.size, report.mechanical.size,
                 "the subtraction and the count agree here only by accident; if they " \
                 "have converged, say so rather than deleting the guard"
  end

  # A layered Law can carry both deterministic and semantic enforcement without
  # becoming two catalogue rules.
  def test_a_law_can_be_semantic_and_mechanical_at_once
    report = audit.call
    law = Master::Review::Scan::Laws::SemanticLaw.new(agent: nil)

    assert_includes report.mechanical, "FAIL_VISIBLY"
    refute_includes report.semantic_only, "FAIL_VISIBLY"
    assert_includes law.send(:load_semantic_laws).keys, "FAIL_VISIBLY"
  end

  def test_ungraphed_laws_is_enumerable
    assert_kind_of Array, audit.ungraphed_law_ids
  end

  def test_source_drift_is_a_three_way_audit
    drift = audit.call.source_drift

    assert_equal %i[law_only registry_only yaml_only], drift.keys.sort
    drift.each_value { |ids| assert_kind_of Array, ids }
    assert_equal drift[:yaml_only].sort, drift[:yaml_only]
    assert_equal drift[:law_only].sort, drift[:law_only]
    assert_equal drift[:registry_only].sort, drift[:registry_only]
  end

  def test_reconciliation_is_an_explicit_gate_not_a_pretty_report
    report = audit.call
    expected = report.source_drift.values.all?(&:empty?) &&
      report.catalogue_integrity_errors.empty?

    assert_equal expected, report.reconciled?
    if report.reconciled?
      assert report.assert_reconciled!
    else
      error = assert_raises(RuntimeError) { report.assert_reconciled! }
      assert_match(/Law catalogue is not reconciled/, error.message)
      refute_empty report.reconciliation_errors
    end
  end

  def test_catalogue_report_separates_declared_gaps_from_real_drift
    snapshot = audit.send(
      :catalogue_report,
      map: {
        "law_trace_ceiling" => 2,
        "laws" => {
          "intentional_gap" => { "status" => "gap", "law_ids" => [] },
          "intentional_unmapped" => { "status" => "unmapped", "law_ids" => [] },
          "scanner_law" => { "status" => "covered", "law_ids" => ["SCANNER_LAW"] },
          "dangling_law" => { "status" => "covered", "law_ids" => ["MISSING_LAW"] }
        }
      },
      executable_ids: Set["EXECUTABLE_LAW"],
      registry_ids: Set["SCANNER_LAW", "UNMAPPED_DETECTOR"]
    )

    assert_equal ["intentional_gap"], snapshot.fetch(:declared_gaps)
    assert_equal ["intentional_unmapped"], snapshot.fetch(:declared_unmapped)
    assert_empty snapshot.fetch(:drift).fetch(:empty_without_declared_gap)
    assert_equal ["executable_law"], snapshot.fetch(:drift).fetch(:executable_not_mapped)
    assert_equal ["missing_law"], snapshot.fetch(:drift).fetch(:mapped_without_enforceable)
    assert_equal ["unmapped_detector"], snapshot.fetch(:trace_debt)
    assert_equal 2, snapshot.fetch(:trace_ceiling)
  end

  def test_catalogue_integrity_gate_rejects_trace_debt_over_its_declared_ceiling
    over_budget = audit.call.with(trace_debt: %w[one two three], trace_ceiling: 2)

    assert_raises(RuntimeError) { over_budget.assert_catalogue_integrity! }
    assert over_budget.catalogue_integrity_errors.any? { |error| error.include?("exceeds declared ceiling") }
  end

  def test_a_law_a_test_defined_is_not_in_the_corpus
    assert_includes Master::Review::Scan::Law.registry, LawDefinedByATest,
                    "the premise: defining the class registers it"

    refute_includes audit.ungraphed_law_ids, "rule_defined_by_a_test"
    refute_includes audit.call.registry_ids, "rule_defined_by_a_test"
  end

  # The counterweight: excluding tests must not exclude the shipped rules, which
  # is how a census gets quiet instead of correct.
  def test_the_shipped_laws_are_still_counted
    ids = audit.call.registry_ids

    assert_operator ids.size, :>, 100
    assert_includes ids, "trailing_whitespace"
    assert_includes ids, "no_god_class"
  end

  # The escape hatch is idle: no rule declares a detect_lexical, so
  # YamlDeclarativeLaw bridges nothing. This is the tripwire — the day somebody
  # declares one, it fails and asks whether the bridge is still wanted.
  def test_the_lexical_hatch_is_empty
    report = audit.call

    assert_empty report.lexical_wired
    assert_empty report.lexical_unwired
  end
end
