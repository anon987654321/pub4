# frozen_string_literal: true

require_relative "dilla_helper"

class TestDillaPostproBridge < Minitest::Test
  EXPECTED = {
    "film_curve" => :hedd_tape,
    "halation" => :space_echo,
    "adjacency_effects" => :console_sum,
    "optical_blur" => :space_echo,
    "spectral_temp" => :gml_matte,
    "expired_film" => :tape_machine,
    "gate_weave" => :tape_machine,
    "print_film" => :hedd_tape,
    "vhs_chroma_delay" => :phase_rotate,
    "grain" => :sample_domain
  }.freeze

  def test_every_translation_is_explicit_and_resolves
    EXPECTED.each do |effect, unit|
      assert_equal unit, Outboard::POSTPRO_ANALOG_TRANSLATIONS.fetch(effect)

      next if unit == :sample_domain

      assert_respond_to Outboard, unit
      assert_kind_of String, Outboard.postpro_translation(effect, bpm: 90)
    end
  end

  def test_grain_stays_in_the_sample_domain
    assert_nil Outboard.postpro_translation("grain", bpm: 90)
    assert_equal "", Outboard.postpro_chain(["grain"], bpm: 90)
  end

  def test_explicit_chain_preserves_stage_order
    chain = Outboard.postpro_chain(%w[film_curve halation adjacency_effects], bpm: 90)

    tape_at = chain.index("asoftclip=")
    echo_at = chain.index("aecho=")
    console_at = chain.index("allpass=f=90")

    refute_nil tape_at
    refute_nil echo_at
    refute_nil console_at
    assert_operator tape_at, :<, echo_at
    assert_operator echo_at, :<, console_at
  end

  def test_named_bridge_racks_are_reachable
    assert_includes Outboard::RACKS.fetch(:postpro_transfer), :hedd_tape
    assert_equal %i[tape_machine program_memory], Outboard::RACKS.fetch(:postpro_wear)
    assert_equal %i[space_echo console_sum], Outboard::RACKS.fetch(:postpro_space)
    assert_includes Outboard.chain(:postpro_wear, bpm: 90), "acompressor="
  end

  def test_program_memory_is_reachable_through_chain
    assert_includes Outboard.chain(:postpro_wear, bpm: 90), "release=420"
  end
end
