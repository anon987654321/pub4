# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestUxRefinementsContract < Minitest::Test
  PATH = File.join(Master::ROOT, "data", "ux_refinements.yml")
  ALLOWED_STATES = %w[acceptance_required implemented verified blocked not_applicable].freeze

  def test_all_ninety_refinements_are_present_and_unique
    catalogue = YAML.safe_load_file(PATH)
    rows = catalogue.fetch("refinements")
    expected_count = catalogue.fetch("expected_count")

    assert_equal 90, expected_count
    assert_equal expected_count, rows.size
    ids = rows.map { |row| row.fetch("id").to_s }.sort
    assert_equal (1..expected_count).map { |number| format("UX%03d", number) }, ids
  end

  def test_each_refinement_has_a_complete_acceptance_contract
    rows = YAML.safe_load_file(PATH).fetch("refinements")
    rows.each do |row|
      id = row.fetch("id")
      %w[area title contract state].each do |key|
        refute_empty row.fetch(key).to_s.strip, "#{id} is missing #{key}"
      end
      assert_kind_of Array, row.fetch("owner_trees"), "#{id} must name its owning tree(s)"
      refute_empty row.fetch("owner_trees"), "#{id} has no owner"
      assert_kind_of Array, row.fetch("proof"), "#{id} must name its required proof"
      refute_empty row.fetch("proof"), "#{id} has no proof method"
      assert_includes ALLOWED_STATES, row.fetch("state").to_s, "#{id} has an unknown acceptance state"

      next unless row.fetch("state").to_s == "verified"

      evidence = row["evidence"]
      assert_kind_of Hash, evidence, "#{id} cannot be verified without a recorded evidence receipt"
      refute_empty evidence.fetch("location", "").to_s.strip, "#{id} evidence needs a location"
      assert_match(/\A[0-9a-f]{64}\z/i, evidence.fetch("sha256", "").to_s, "#{id} evidence needs a SHA-256 digest")
    end
  end
end
