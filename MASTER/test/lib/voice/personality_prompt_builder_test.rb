# frozen_string_literal: true

require_relative "../../test_helper"

class TestPersonalityPromptBuilder < Minitest::Test
  # OpenClaw-inspired core-vs-contextual split (item #9): every persona
  # (lawyer, medic, trader, architect...) previously got the same
  # unconditional Ruby/CSS/HTML/design-rules block stapled onto its prompt
  # regardless of domain. context: :core strips that contextual block;
  # context: :full (the default, used by every current call site) must stay
  # byte-for-byte identical to pre-split behavior.
  def test_full_context_matches_default_and_includes_style_rules
    persona = Master::Voice::Personality.new(:anchor)
    default_prompt = persona.system_prompt
    full_prompt = Master::Voice::Personality.new(:anchor).system_prompt(context: :full)

    assert_equal default_prompt, full_prompt
    assert_includes full_prompt, "master_style"
  end

  def test_core_context_omits_code_and_design_style
    persona = Master::Voice::Personality.new(:lawyer)
    core_prompt = persona.system_prompt(context: :core)

    refute_includes core_prompt, "<master_style>"
  end

  def test_core_context_keeps_constitution_and_output_contract
    persona = Master::Voice::Personality.new(:medic)
    core_prompt = persona.system_prompt(context: :core)

    assert_includes core_prompt, "master_constitution"
    assert_includes core_prompt, "master_output_format"
  end

  def test_core_and_full_are_cached_independently
    persona = Master::Voice::Personality.new(:trader)
    core = persona.system_prompt(context: :core)
    full = persona.system_prompt(context: :full)

    refute_equal core, full
    assert_same core, persona.system_prompt(context: :core)
    assert_same full, persona.system_prompt(context: :full)
  end
end
