# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestLawsReflow < Minitest::Test
  RANKED_LAWS = %w[
    CAPABILITY_STATUS_MUST_BE_TRUTHFUL
    ROBUSTNESS
    SINGULARITY
    LINEARITY
    PROXIMITY
    ABSTRACTION
    DENSITY
    RENDERED_VALUES
    INTER_MODEL_CONTRACT
  ].freeze

  # The file's own header promises the nine priority-ranked laws (eight operating
  # principles plus the inter-model protocol) come first and that everything
  # after them is an execution-policy block.
  def test_ranked_laws_come_first_then_policy_blocks
    path = File.join(Master::ROOT, "data", "laws.yml")
    body = File.read(path, encoding: "UTF-8")
    keys = body.scan(/^([A-Za-z_][A-Za-z0-9_-]*):\s*$/).flatten

    assert_equal RANKED_LAWS, keys.first(RANKED_LAWS.size)
    assert keys.drop(RANKED_LAWS.size).all? { |key| key.match?(/\A[a-z][a-z0-9_]*\z/) },
           "a block after the ranked laws is not a lower-case policy block"
  end

  def test_policy_file_remains_valid_yaml
    path = File.join(Master::ROOT, "data", "laws.yml")
    data = YAML.safe_load_file(path, aliases: true)

    assert_kind_of Hash, data
  end

  def test_policy_reflow_does_not_duplicate_top_level_keys
    path = File.join(Master::ROOT, "data", "laws.yml")
    body = File.read(path, encoding: "UTF-8")
    keys = body.scan(/^([A-Za-z_][A-Za-z0-9_-]*):\s*$/).flatten

    assert_equal keys.uniq.sort, keys.sort
  end
end
