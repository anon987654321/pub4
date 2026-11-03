# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/convergence/workstreams"

class TestConvergenceWorkstreams < Minitest::Test
  def test_registry_has_unique_ids_and_honest_states
    items = Master::Convergence::Workstreams.items(root: Master::ROOT)
    assert_operator items.size, :>=, 20
    assert_equal items.map { |item| item[:id] }.uniq.size, items.size
    items.each { |item| assert_includes Master::Convergence::STATES.map(&:to_s), item[:state] }
  end

  def test_render_can_filter_one_workstream
    result = Master::Convergence::Workstreams.render("snapshot_exchange", root: Master::ROOT)
    assert_includes result, "snapshot_exchange"
    assert_includes result, "share-safe"
  end

  # The 2026-11-03 architecture review landed as design of record: rows that
  # name where their proof will live. A row leaves missing only in the commit
  # that adds its proof — the same signed edit a ratchet ceiling is.
  REVIEW_DESIGN_OF_RECORD = %w[
    inconclusive_aging
    constitution_self_budget
    documentation_completeness
    ops_alert_channel
  ].freeze

  def test_review_rows_stay_missing_until_their_proof_exists
    items = Master::Convergence::Workstreams.items(root: Master::ROOT)
    rows = REVIEW_DESIGN_OF_RECORD.map { |id| items.find { |item| item[:id] == id } }

    rows.each do |row|
      refute_nil row, "a review design-of-record row was deleted from convergence.yml"
      assert_equal "missing", row[:state], "#{row[:id]} leaves missing only in the commit that adds its proof"
      refute_empty row[:implementation], "#{row[:id]} names no implementation"
      refute_empty row[:proof], "#{row[:id]} names no proof"
    end
  end
end
