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

  def test_catalogue_declaration_uses_shared_loader_across_sections
    catalogue = {
      "laws" => { "CANONICAL_LAW" => { "statement" => "Canonical entry" } },
      "beauty" => [{ "id" => "BEAUTY_LAW", "statement" => "Beauty entry" }],
      "anti_patterns" => { "UNSAFE_PATTERN" => { "statement" => "Pattern entry" } },
    }
    observed_root = nil
    loader = lambda do |root:|
      observed_root = root
      catalogue
    end

    Master.stub(:load_laws, loader) do
      canonical = Operator::LawInventory.catalogue_declaration("canonical_law", root: "/tmp/custom-master")
      beauty = Operator::LawInventory.catalogue_declaration("beauty_law", root: "/tmp/custom-master")
      pattern = Operator::LawInventory.catalogue_declaration("unsafe_pattern", root: "/tmp/custom-master")

      assert_equal "CANONICAL_LAW", canonical.fetch("id")
      assert_equal "BEAUTY_LAW", beauty.fetch("id")
      assert_equal "UNSAFE_PATTERN", pattern.fetch("id")
    end
    assert_equal "/tmp/custom-master", observed_root
  end

  def test_catalogue_declaration_refuses_an_empty_catalogue
    Master.stub(:load_laws, ->(root:) { {} }) do
      assert_raises(RuntimeError) do
        Operator::LawInventory.catalogue_declaration("MISSING_LAW", root: "/tmp/empty-master")
      end
    end
  end

  def test_council_rows_uses_shared_yaml_loader
    observed_path = nil
    loader = lambda do |path, **_options|
      observed_path = path
      { "personas" => [{ "name" => "Operator" }, { "name" => "Reviewer" }] }
    end

    Master.stub(:load_yaml, loader) do
      rows = Operator::LawInventory.council_rows
      assert_equal %w[Operator Reviewer], rows.map { |row| row.fetch("name") }
    end
    assert_equal Master::COUNCIL_PATH, observed_path
  end

  # Reach is a firing rate, so it is measured on a Law with a detector;
  # ONE_SOURCE is judged semantically and has no rate to report.
  def test_health_reach_uses_the_live_law_audit
    row = Operator::LawInventory.health("FAIL_VISIBLY")
    refute_nil row
    assert_operator row.fetch(:health).fetch(:applicable), :>, 0
    assert row.fetch(:health).key?(:hits)
  end

  def test_matrix_is_derived_from_council_axes
    matrix = Operator::LawInventory.matrix
    assert_operator matrix.size, :>, 5
    assert matrix.all? { |row| row[:persona] && row[:axes] && row[:rules] }
  end
end
