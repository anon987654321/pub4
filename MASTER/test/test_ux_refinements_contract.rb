# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestUxRefinementsContract < Minitest::Test
  PATH = File.join(Master::ROOT, "data", "ux_refinements.yml")
  ALLOWED_STATES = %w[acceptance_required verified].freeze

  def catalogue
    YAML.safe_load_file(PATH)
  end

  def test_all_ninety_refinements_are_present_and_unique
    data = catalogue
    rows = data.fetch("refinements")
    expected_count = data.fetch("expected_count")

    assert_equal 90, expected_count
    assert_equal expected_count, rows.size
    ids = rows.map { |row| row.fetch("id").to_s }.sort
    assert_equal (1..expected_count).map { |number| format("UX%03d", number) }, ids
  end

  def test_each_refinement_has_a_complete_acceptance_contract
    catalogue.fetch("refinements").each do |row|
      id = row.fetch("id")
      %w[area title contract state].each do |key|
        refute_empty row.fetch(key).to_s.strip, "#{id} is missing #{key}"
      end

      assert_kind_of Array, row.fetch("owner_trees"), "#{id} must name its owner trees"
      refute_empty row.fetch("owner_trees"), "#{id} has no owner"
      assert_kind_of Array, row.fetch("proof"), "#{id} must name its required proof"
      refute_empty row.fetch("proof"), "#{id} has no proof method"
      assert_includes ALLOWED_STATES, row.fetch("state").to_s, "#{id} has an unknown state"

      next unless row.fetch("state").to_s == "verified"

      evidence = row["evidence"]
      assert_kind_of Array, evidence, "#{id} cannot be verified without evidence receipts"
      proof_types = evidence.map do |receipt|
        assert_kind_of Hash, receipt, "#{id} evidence receipt must be a mapping"
        assert_equal "PASS", receipt.fetch("result")
        assert_includes row.fetch("proof"), receipt.fetch("proof_type")
        refute_empty receipt.fetch("location", "").to_s.strip
        assert_match(/\A[0-9a-f]{64}\z/i, receipt.fetch("sha256", "").to_s)
        assert_match(/\A[0-9a-f]{40}\z/i, receipt.fetch("commit", "").to_s)
        receipt.fetch("proof_type")
      end
      assert_empty Array(row.fetch("proof")).map(&:to_s).uniq - proof_types.uniq,
                   "#{id} has no evidence receipt for every declared proof type"
    end
  end

  def test_acceptance_required_remains_the_initial_state_for_unverified_rows
    catalogue.fetch("refinements").each do |row|
      next if row.fetch("state") == "verified"

      assert_equal "acceptance_required", row.fetch("state"),
                   "#{row.fetch("id")} needs implementation and recorded acceptance evidence before promotion"
    end
  end
end
