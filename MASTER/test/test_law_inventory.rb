# frozen_string_literal: true

require_relative "test_helper"
require "operator/law_inventory"

class TestLawInventory < Minitest::Test
  def test_inventory_joins_existing_sources_without_owning_rule_data
    rows = Operator::LawInventory.all
    assert_operator rows.size, :>, 100
    row = rows.values.find { |item| item[:id].to_s.casecmp?("ONE_SOURCE") }
    refute_nil row
    assert_equal true, row[:executable_law] || row[:scanner]
  end

  def test_health_reports_derived_shape
    row = Operator::LawInventory.health("ONE_SOURCE")
    refute_nil row
    assert_equal "ONE_SOURCE", row[:id]
    assert row.key?(:twin)
    assert row.key?(:history)
  end

  def test_matrix_is_derived_from_council_axes
    matrix = Operator::LawInventory.matrix
    assert_operator matrix.size, :>, 5
    assert matrix.all? { |row| row[:persona] && row[:axes] && row[:rules] }
  end
end
