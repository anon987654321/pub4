# frozen_string_literal: true

require_relative "test_helper"

# The respelling table is the only pronunciation control available: rb_edge_tts
# takes plain text, so there is no SSML and no <phoneme>. That makes a wrong
# entry worse than a missing one, and makes matching precision the whole risk.
class TestLexicon < Minitest::Test
  L = Master::Voice::Lexicon

  def test_the_shipped_table_loads_and_is_not_empty
    refute_empty L.table
  end

  # An entry whose respelling equals its written form does nothing but slow the
  # pattern down and hide that nobody checked it.
  def test_no_entry_respells_a_word_as_itself
    noops = L.table.select { |written, spoken| written.casecmp?(spoken) }

    assert_empty noops, "these entries change nothing"
  end

  def test_a_known_daemon_name_is_respelled
    assert_equal "relay D is a proxy.", L.apply("relayd is a proxy.")
  end

  # Longest key first, or DNSSEC is consumed by DNS and the tail is left behind.
  def test_a_longer_key_wins_over_a_prefix_of_it
    assert_equal "DNS sec", L.apply("DNSSEC")
  end

  def test_respelling_does_not_reach_inside_a_longer_word
    assert_equal "brgenerated", L.apply("brgenerated")
    assert_equal "unrelayded", L.apply("unrelayded")
  end

  def test_hyphenated_neighbours_are_left_alone
    assert_equal "post-relayd-hook", L.apply("post-relayd-hook")
  end

  def test_an_unknown_word_passes_through_untouched
    text = "The pipeline resolved without incident."

    assert_equal text, L.apply(text)
  end

  def test_numeronyms_are_spoken_as_words
    assert_equal "accessibility and internationalization", L.apply("a11y and i18n")
  end

  def test_matching_is_case_insensitive_but_prefers_the_exact_key
    assert_equal "Open B S D", L.apply("OpenBSD")
    assert_equal "Open B S D", L.apply("openbsd")
  end

  def test_punctuation_around_a_match_survives
    assert_equal "(Postgres), Bergen.", L.apply("(PostgreSQL), brgen.")
  end

  # clean_text is the one chokepoint every synthesis entry point passes through,
  # which is why the pass lives at its tail rather than in each caller.
  def test_clean_text_applies_the_lexicon
    assert_includes Master::Voice::Speech.clean_text("Restarting relayd now."), "relay D"
  end

  def test_clean_text_still_strips_what_it_stripped_before
    cleaned = Master::Voice::Speech.clean_text("See https://example.com and ```x = 1``` now.")

    assert_includes cleaned, "link omitted"
    assert_includes cleaned, "code omitted"
  end

  def test_an_absent_table_is_not_an_error
    original = L.table
    L.instance_variable_set(:@table, {})
    L.instance_variable_set(:@pattern, nil)

    assert_equal "relayd", L.apply("relayd")
  ensure
    L.instance_variable_set(:@table, original)
    L.instance_variable_set(:@pattern, nil)
  end
end
