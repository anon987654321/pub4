# frozen_string_literal: true

require_relative "test_helper"
require File.join(Master::ROOT, "law", "law")
require "yaml"

class TestFixHygiene < Minitest::Test
  def test_convergence_uses_a_finite_unmeasured_score
    source = File.read(File.join(Master::ROOT, "lib", "fix", "convergence_discipline.rb"))

    assert_includes source, "UNMEASURED_SCORE = 1_000_000_000"
    refute_includes source, "state_for(0, Float::INFINITY"
    assert_includes source, "def score_value(score)"
  end

  def test_convergence_reasoning_contract_loads_the_canonical_hygiene_prompt
    config = Master.load_yaml(File.join(Master::ROOT, "data", "fix_hygiene.yml"))
    prompt = config.fetch("llm_prompt")
    discipline = Master::Fix::ConvergenceDiscipline.new(root: Master::REPO_ROOT)

    contract = discipline.send(:reasoning_contract, strategy: :consensus, files: [], findings: [])

    assert_includes prompt, "numeric ranks"
    assert_includes prompt, "Deterministic census beats LLM invention"
    assert_includes contract, prompt
    assert_includes contract, "data/event_topics.yml"
  end

  def test_hygiene_laws_are_loaded_and_prove_their_polarity
    Law.load_all(File.join(Master::ROOT, "law"))

    assert Law.rules.key?(:NO_INFINITY_TO_I)
    assert Law.rules.key?(:NO_OVERESCAPED_NONCAPTURING)
    assert Law.rules.fetch(:NO_INFINITY_TO_I).scan("Float::INFINITY.to_i").any?
    assert_empty Law.rules.fetch(:NO_INFINITY_TO_I).scan("value.to_i")
    assert Law.rules.fetch(:NO_OVERESCAPED_NONCAPTURING).scan('body.scan(/phantom:\\\\(?:detected|halt|recovery)/)').any?
  end

  def test_hygiene_prompt_mode_points_at_the_canonical_data
    prompts = Master.load_yaml(Master::PROMPTS_PATH)
    mode = prompts.fetch("fix_hygiene")

    assert_equal "MASTER/data/fix_hygiene.yml", mode.fetch("source")
    refute_includes mode.fetch("template"), "numeric ranks: never"
    assert_includes mode.fetch("template"), "%{message}"
  end

  def test_event_topics_contract_is_data_not_commentary
    topics = Master.load_yaml(File.join(Master::ROOT, "data", "event_topics.yml"))

    assert_equal 1, topics.fetch("schema")
    assert_equal ["phantom:retry", "pipeline:start"], topics.fetch("retired")
    assert_equal "web/public/visual_bridge.js", topics.fetch("reference_anchors").fetch("phantom:recovery")
    assert_includes topics.fetch("publishers").fetch("phantom"), "phantom:detected"
  end
end
