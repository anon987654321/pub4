# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestLawsReflow < Minitest::Test
  def test_nine_invariant_nodes_are_first_and_follow_document_order
    data = Master.load_yaml(File.join(Master::ROOT, "data", "laws.yml"))
    node_ids = data.filter_map { |id, row| id if row.is_a?(Hash) && row["node"] }

    assert_equal 9, node_ids.size
    assert_equal Master::Soul.invariant_order.map(&:upcase), node_ids
    assert_operator data.keys.index("SACRED_AUTHORSHIP"), :>, data.keys.index(node_ids.last)
  end

  def test_laws_yml_is_a_valid_self_governing_flat_catalogue
    data = YAML.safe_load_file(File.join(Master::ROOT, "data", "laws.yml"), aliases: true)

    assert_kind_of Hash, data
    assert Master::FlatLawCatalogue.validate!(data)
  end

  def test_catalogue_has_no_retired_numeric_ranking_or_path_scope
    source = File.read(File.join(Master::ROOT, "data", "laws.yml"), encoding: "UTF-8")

    refute_match(/^\s+(?:priority|tier):/m, source)
    refute_match(/^\s+(?:applies_to|domain|path|path_pattern|exclude):/m, source)
  end

  def test_source_does_not_declare_duplicate_top_level_law_ids
    source = File.read(File.join(Master::ROOT, "data", "laws.yml"), encoding: "UTF-8")
    ids = source.lines.filter_map do |line|
      match = line.match(/\A([A-Z][A-Za-z0-9_]*):\s*\z/)
      match && match[1]
    end

    assert_equal ids.uniq.sort, ids.sort
  end
end
