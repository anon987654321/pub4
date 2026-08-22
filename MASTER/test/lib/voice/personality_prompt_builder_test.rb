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

  # rules.yml style.typography puts the scale at typography.scale.ratio; this
  # line read typography["ratio"], one level too shallow, so the hardcoded 1.25
  # fallback was the only value the prompt ever carried and editing the section
  # did nothing. `measure` and `leading` were literals beside it for the same reason.
  class Typographer
    include Master::Voice::PersonalityPromptBuilder
    public :typography_style_line
  end

  def test_typography_line_reads_style_yml_rather_than_its_own_fallbacks
    line = Typographer.new.typography_style_line(
      "style" => "brutalist",
      "families_sans" => "Inter",
      "scale_base" => "18px",
      "scale_ratio" => 1.618,
      "leading" => 1.35,
      "measure" => "72ch"
    )

    assert_includes line, "brutalist style"
    assert_includes line, "Inter"
    assert_includes line, "scale 18px × 1.618"
    assert_includes line, "leading 1.35"
    assert_includes line, "measure 72ch"
  end

  def test_typography_line_matches_the_committed_style_yml
    typography = Master.law("style").fetch("typography")
    line = Typographer.new.typography_style_line(typography)

    assert_includes line, "scale #{typography.fetch("scale_base")} × #{typography.fetch("scale_ratio")}"
    assert_includes line, "measure #{typography.fetch("measure")}"
  end

  def test_typography_line_still_degrades_without_a_scale
    line = Typographer.new.typography_style_line("families_sans" => "Inter")

    assert_includes line, "swiss style"
    assert_includes line, "× 1.25"
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
