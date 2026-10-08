# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestLawsReflow < Minitest::Test
  EXPECTED_ORDER = %w[
    transformation_policy
    CAPABILITY_STATUS_MUST_BE_TRUTHFUL
    ROBUSTNESS
    SINGULARITY
    LINEARITY
    PROXIMITY
    ABSTRACTION
    DENSITY
    prose
    RENDERED_VALUES
    architecture
    runtime_policy
    self_test
    plugins
    tokens
    veto_patterns
    anti_patterns
    rule_deps
  ].freeze

  def test_policy_blocks_are_reflowed_by_importance
    path = File.join(Master::ROOT, "data", "laws.yml")
    body = File.read(path, encoding: "UTF-8")
    keys = body.scan(/^([A-Za-z_][A-Za-z0-9_-]*):\s*$/).flatten

    assert_equal EXPECTED_ORDER, keys
  end

  def test_policy_file_remains_valid_yaml
    path = File.join(Master::ROOT, "data", "laws.yml")
    data = YAML.safe_load_file(path, aliases: true)

    assert_kind_of Hash, data
    assert_equal 1, data["schema"]
  end

  def test_policy_reflow_does_not_duplicate_top_level_keys
    path = File.join(Master::ROOT, "data", "laws.yml")
    body = File.read(path, encoding: "UTF-8")
    keys = body.scan(/^([A-Za-z_][A-Za-z0-9_-]*):\s*$/).flatten

    assert_equal keys.uniq.sort, keys.sort
  end
end
