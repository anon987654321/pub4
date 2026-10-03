# frozen_string_literal: true

require_relative "dilla_helper"

# Song form comes in through two knobs that disagree about precedence
# (SECTION_MAP wins over FORM) and one memoised reader, and the memo is on the
# main object rather than on an instance -- so a form resolved once in a process
# is the form for the rest of it. The stream re-execs itself, which is the only
# reason that has not bitten harder than it has.
class TestFormMap < Minitest::Test
  def reset_form!
    return unless instance_variable_defined?(:@resolve_form_map)

    remove_instance_variable(:@resolve_form_map)
  end

  # resolve_form_map memoises onto whatever object called it. These tests call
  # it on the test case, so the memo is the test case's and clearing it is
  # enough; the engine's own copy is untouched.
  def setup
    reset_form!
  end

  def teardown
    reset_form!
  end

  def test_a_section_map_parses_into_ordered_kind_length_pairs
    assert_equal [[:intro, 8], [:main, 16], [:outro, 4]],
                 send(:parse_section_map!, "intro:8,main:16,outro:4")
  end

  def test_parsing_tolerates_whitespace_and_case
    assert_equal [[:intro, 8], [:main, 16]],
                 send(:parse_section_map!, " Intro:8 , MAIN:16 ")
  end

  # Named aliases exist because the sections are written A / A2 / B on paper.
  def test_the_lead_sheet_letters_resolve_to_section_kinds
    assert_equal [[:main, 8], [:build, 8], [:turn, 4]],
                 send(:parse_section_map!, "a:8,a2:8,b:4")
    assert_equal [[:turn, 4]], send(:parse_section_map!, "turnaround:4")
  end

  def test_a_malformed_entry_is_dropped_rather_than_rendering_a_zero_bar_section
    assert_equal [[:main, 16]], send(:parse_section_map!, "main:16,nonsense")
    assert_empty send(:parse_section_map!, "")
  end

  def test_the_section_map_outranks_the_form_preset
    with_env("SECTION_MAP" => "main:4", "FORM" => "camel_32") do
      assert_equal [[:main, 4]], send(:resolve_form_map)
    end
  end

  def test_a_form_preset_resolves_when_no_section_map_is_given
    with_env("SECTION_MAP" => nil, "FORM" => "camel_32") do
      assert_equal FORM_PRESETS[:camel_32][:map], send(:resolve_form_map)
    end
  end

  def test_an_unknown_form_resolves_to_nothing_rather_than_to_a_default_no_one_asked_for
    with_env("SECTION_MAP" => nil, "FORM" => "not_a_form") do
      assert_nil send(:resolve_form_map)
    end
  end

  def test_the_section_at_a_bar_walks_the_map_and_then_cycles
    with_env("SECTION_MAP" => "intro:2,main:4,outro:2") do
      assert_equal :intro, send(:form_section_at, 0, 64)
      assert_equal :intro, send(:form_section_at, 1, 64)
      assert_equal :main, send(:form_section_at, 2, 64)
      assert_equal :main, send(:form_section_at, 5, 64)
      assert_equal :outro, send(:form_section_at, 6, 64)
      assert_equal :intro, send(:form_section_at, 8, 64), "bar 8 is the top of the second cycle"
    end
  end

  def test_no_form_means_no_section_rather_than_a_guessed_one
    with_env("SECTION_MAP" => nil, "FORM" => nil) do
      assert_nil send(:form_section_at, 3, 64)
    end
  end

  def test_every_shipped_preset_declares_a_non_empty_cycle
    FORM_PRESETS.each do |name, preset|
      map = preset[:map]
      refute_nil map, "#{name} has no map"
      refute_empty map
      assert_operator map.sum { |_, len| len }, :>, 0, "#{name} has a zero-bar cycle and never advances"
      map.each { |kind, len| assert_kind_of(Symbol, kind) and assert_operator(len, :>, 0) }
    end
  end

  def test_a_preset_widens_the_phrase_without_discarding_the_callers_config
    cfg = { intro_bars: 1, phrase_bars: 1, tempo: 91 }
    with_env("FORM" => "camel_32") do
      out = send(:apply_form_to_cfg!, cfg)
      assert_equal 8, out[:intro_bars]
      assert_equal 32, out[:phrase_bars]
      assert_equal 91, out[:tempo], "a form preset dropped a key it does not own"
      assert_equal :camel_32, out[:form]
    end
  end

  def test_a_render_mode_selects_a_form_when_none_was_named
    with_env("FORM" => nil, "RENDER_MODE" => "camel") do
      assert_equal 32, send(:apply_form_to_cfg!, { intro_bars: 1, phrase_bars: 1 })[:phrase_bars]
    end
  end

  def test_an_unknown_mode_leaves_the_config_alone
    cfg = { intro_bars: 1, phrase_bars: 1 }
    with_env("FORM" => nil, "RENDER_MODE" => "something_else") do
      assert_same cfg, send(:apply_form_to_cfg!, cfg)
    end
  end

  # Phrase-locked recall: the same four-note figure whenever the same chord
  # symbol returns. It keys off a symbol with the pedal and transposition
  # suffixes stripped, so a pedal restatement recalls the original figure.
  def test_chord_symbols_normalise_past_pedal_and_transposition_suffixes
    assert_equal "dbmaj7", send(:chord_symbol_key, { name: "dbmaj7_pedal" })
    assert_equal "dbmaj7", send(:chord_symbol_key, { name: "dbmaj7_t3" })
    assert_equal "dbmaj7", send(:chord_symbol_key, { name: "dbmaj7" })
  end

  def test_a_chord_with_no_pitches_gets_the_neutral_motif
    assert_equal [0, 1, 2, 1], send(:motif_from_chord, nil)
    assert_equal [0, 1, 2, 1], send(:motif_from_chord, { hz: [] })
  end

  def test_a_wide_chord_reaches_its_fourth_tone
    assert_equal [0, 1, 2, 3], send(:motif_from_chord, { hz: [110.0, 130.0, 165.0, 196.0] })
    assert_equal [0, 1, 2, 1], send(:motif_from_chord, { hz: [110.0, 130.0, 165.0] })
  end
end
