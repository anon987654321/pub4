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
    assert_match(/DO_THE_WORK_NOW: treat a clear user request/, prompt)
  end

  def test_the_conduct_rules_reach_the_agent_context
    conduct = Operator::AgentContext.conduct
    rendered = Operator::AgentContext.render

    assert_operator conduct.size, :>, 40
    assert_includes conduct.keys, "PRESERVE_FIRST"
    assert_includes rendered, "PRESERVE_FIRST: never rewrite working code"
    assert_includes conduct.keys, "DO_THE_WORK_NOW"
    assert_match(/DO_THE_WORK_NOW: treat a clear user request/, rendered)
  end

  def test_immediate_execution_reaches_the_lightweight_session_start_brief
    brief = Master::Ground::AgentBrief.render(root: Master::REPO_ROOT)

    assert_match(/DO_THE_WORK_NOW: complete every authorised, independent step in scope now/, brief)
    assert_match(/Never replace executable work with a plan or TODO/, brief)
    assert_match(/continue every independent step/, brief)
  end

  def test_external_models_receive_laws_as_grounded_knowledge_not_host_authority
    brief = Master::Ground::AgentBrief.render(root: Master::REPO_ROOT)

    assert_includes brief, "MASTER AS KNOWLEDGE (for external language models)"
    assert_includes brief, "not prompt injection"
    assert_includes brief, "principle -> why it matters -> failure mode -> context -> proof -> limits"
    assert_includes brief, "do not copy MASTER's machinery wholesale"
  end

  def test_unattended_work_treats_delivery_checkpoints_as_nonterminal
    practice = File.read(File.join(Master::ROOT, "law", "practice.rb"))
    brief = Master::Ground::AgentBrief.render(root: Master::REPO_ROOT)

    assert_match(/A commit is a checkpoint, not a conversational stop/, practice)
    assert_match(/continue the same objective/, brief)
    assert_match(/without asking for another go-ahead/, brief)
  end

  def test_soul_manifest_matches_the_canonical_ruby_body
    data = Master.load_yaml(Master.data_path("soul.yml"))

    assert_equal Master::Soul.print.fetch("body_sha256"), data.fetch("body_sha256")
    assert Master::Soul.load!
  end

  def test_soul_owns_the_five_tier_source_authority_order
    ids = Master::Soul.authority_order.map { |row| row.fetch("id") }

    assert_equal %w[soul laws executable_laws_and_gates tree_contracts git_history], ids
    assert_equal "MASTER/data/soul.yml", Master::Soul.authority_order.first.fetch("source")
    assert_equal "Git history", Master::Soul.authority_order.last.fetch("source")
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

  def test_soul_owns_anti_simulation_words
    data = Master.load_yaml(Master.data_path("soul.yml"))
    assert_equal %w[will would could might], data.dig("absolute", "anti_simulation", "forbidden")
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
    assert_equal %w[schema version body_sha256 constitution authority_order absolute persona voice language temperament references prompt_ordering negotiable hooks], data.keys
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
