# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../../kernel/master"

# The evidence weights live in exactly one Ruby place — Memory::SCORING — and the
# lib spine still reads data/rules.yml's evidence_scoring. Until that spine is
# severed the two must agree, or the agent is told one threshold and judged by
# another. This test is the seam that keeps them honest.
class EvidencePolicyTest < Minitest::Test
  DATA = YAML.safe_load_file(
    File.expand_path("../../data/rules.yml", __dir__), aliases: true
  ).fetch("evidence_scoring")

  def test_weights_match_rules_yaml
    yaml_weights = DATA.fetch("weights").transform_keys(&:to_sym)
    assert_equal Master::Kernel::Memory::SCORING, yaml_weights
  end

  def test_pass_threshold_matches_rules_yaml
    assert_equal DATA.fetch("pass_threshold"), Master::Kernel::Memory::PASS_THRESHOLD
  end

  def test_model_prompt_is_built_from_the_policy_not_restated
    prompt = Master::Kernel::Model::SYSTEM
    assert_includes prompt, "threshold #{Master::Kernel::Memory::PASS_THRESHOLD}"
    Master::Kernel::Memory::SCORING.each do |kind, weight|
      assert_includes prompt, "#{kind}=#{weight}"
    end
  end
end
