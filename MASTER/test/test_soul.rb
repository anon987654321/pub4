# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/agent_context"

class TestSoul < Minitest::Test
  def test_every_executable_rule_reaches_the_system_prompt
    prompt = Master::Voice::Personality.new.send(:build_system_prompt, context: :full)
    laws = Master::Ground::Laws.new.laws

    refute_empty laws, "the executable Law registry must load"
    missing = laws.keys.reject { |id| prompt.include?(id) }
    assert_empty missing, "laws absent from the prompt: #{missing.first(5).join(', ')}"
  end

  def test_the_conduct_rules_reach_the_agent_context
    conduct = Operator::AgentContext.conduct

    assert_operator conduct.size, :>, 40
    assert_includes conduct.keys, "PRESERVE_FIRST"
    assert_includes Operator::AgentContext.render, "PRESERVE_FIRST: never rewrite working code"
  end

  def test_soul_manifest_matches_the_canonical_ruby_body
    data = Master.load_yaml(Master.data_path("soul.yml"))

    assert_equal Master::Soul.print.fetch("body_sha256"), data.fetch("body_sha256")
    assert Master::Soul.load!
  end

  def test_constitutional_precedence_is_a_healthy_nine_node_graph
    expected = %w[
      truthful_status robustness singularity linearity proximity abstraction
      density operator_rendered inter_model_contract
    ]

    assert_equal expected, Master::Soul.invariant_order
    assert Master::Soul.dominates?(:truthful_status, :inter_model_contract)
    refute Master::Soul.dominates?(:inter_model_contract, :truthful_status)
    assert_equal :truthful_status, Master::Soul.winner(:truthful_status, :robustness)
  end

  def test_soul_write_guard_protects_the_ruby_authority
    assert Master::Soul.sacred?("lib/soul.rb")
    refute Master::Soul.sacred?("lib/fix/fix_loop.rb")
    assert_raises(Master::Soul::ProtectedWrite) { Master::Soul.refuse_write!("lib/soul.rb") }
    assert_nil Master::Soul.refuse_write!("lib/fix/fix_loop.rb")
  end

  def test_soul_yaml_contains_only_the_manifest_and_compatibility_settings
    data = Master.load_yaml(Master.data_path("soul.yml"))

    refute data.key?("evolution_log"), "Git is the history of Soul"
    refute data.key?("research"), "research is not constitutional identity"
    refute data.fetch("negotiable").key?("tts_voice"), "voice has one authority at the top level"
    assert_equal %w[schema version body_sha256 persona voice language temperament absolute prompt_ordering negotiable hooks], data.keys
  end

  def test_soul_temperament_is_live_and_keeps_its_restraint
    prompt = Master::Soul.prompt

    assert_includes prompt, "Profile: The exacting observer"
    assert_includes prompt, "Let the absurdity disclose itself"
    assert_includes prompt, "Drop the comic register entirely"
    assert_includes prompt, "Never sacrifice factual accuracy, compassion, clarity or usefulness"
  end

  def test_summary_reports_the_ruby_owned_identity
    summary = Master::Voice::Soul.new.summary

    assert summary.start_with?("soul0: rev #{Master::Soul::VERSION}, persona anchor\n")
    assert_includes summary, Master::Soul::IDENTITY
    refute_includes summary, "SOUL.md"
  end

  def test_proposals_cannot_rewrite_their_own_authority
    soul = Master::Voice::Soul.new

    assert_match(/BLOCKED/, soul.propose("change the identity"))
    assert_match(/BLOCKED/, soul.approve)
    assert_match(/BLOCKED/, soul.rollback)
  end

  def test_soul_system_prompt_comes_from_the_canonical_source
    assert_equal Master::Soul.prompt, Master::Voice::Soul.new.system_prompt
  end

  def test_markdown_identity_documents_are_retired
    refute File.exist?(Master.data_path("SOUL.md"))
    refute File.exist?(Master.data_path("IDENTITY.md"))
  end
end
