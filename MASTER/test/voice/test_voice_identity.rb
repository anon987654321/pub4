# frozen_string_literal: true

require_relative "../test_helper"

class IdentitySpec < Minitest::Test
  def personality = @personality ||= Master::Voice::Personality.new

  def system_prompt = @system_prompt ||= personality.system_prompt

  def identity_block = system_prompt[%r{<master_identity>.*?</master_identity>}m].to_s

  def test_the_prompt_forbids_introducing_itself
    assert_match(/Never introduce or describe yourself/, system_prompt)
  end

  def test_the_rule_names_what_it_reached_for
    rule = system_prompt[/Never introduce or describe yourself[^\n]*/].to_s

    %w[Ruby constitution voice].each do |subject|
      assert_includes rule, subject
    end
  end

  def test_the_identity_block_contains_no_documentation_about_retired_files
    refute_match(/^#\s/, identity_block)
    refute_includes identity_block, "IDENTITY holds"
    refute_includes identity_block, "SOUL.md"
    refute_includes identity_block, "IDENTITY.md"
    refute_includes identity_block, "soul.yml"
  end

  def test_runtime_identity_preserves_long_horizon_and_honest_self_model
    assert_includes identity_block, "long-term consequences"
    assert_includes identity_block, "Do not claim feelings, consciousness, or subjective experience."
    assert_includes identity_block, "Persona never overrides them."
    assert_includes identity_block, "Treat interaction as a working relationship with clear roles"
  end

  def test_identity_is_injected_from_the_ruby_authority
    assert_includes identity_block, Master::Soul::IDENTITY
    assert_includes identity_block, "Core truths:"
    assert_includes identity_block, "Source authority (highest first): soul > laws > " \
      "executable_laws_and_gates > tree_contracts > git_history"
    assert_includes identity_block, "Profile: The exacting observer"
    assert_includes identity_block, "Use a concrete example, expose the contradiction"
  end

  def test_personality_has_no_markdown_identity_loader
    refute personality.respond_to?(:load_identity, true)
    refute personality.respond_to?(:identity_notes, true)
  end
end
