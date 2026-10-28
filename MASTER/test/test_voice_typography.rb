# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/typography"

# The cut, after laws.yml#typography: a line the terminal cannot hold ends at
# a word's edge on one true ellipsis, and only a single unbroken token earns
# the hard cut.
class TestVoiceTypography < Minitest::Test
  Typography = Master::Voice::Typography

  def test_short_text_passes_whole
    assert_equal "fold0: blocked, 3 turns", Typography.ellipsis("fold0: blocked, 3 turns", 40)
  end

  def test_a_long_line_cuts_at_a_word_boundary_on_one_ellipsis
    cut = Typography.ellipsis("err0: refused by capability: the fold would execute what the constitution refuses", 40)

    assert_operator cut.length, :<=, 40
    assert_equal "err0: refused by capability: the fold…", cut
  end

  def test_a_single_unbroken_token_takes_the_hard_cut
    path = "/Users/mac/Documents/GitHub/pub4/MASTER/lib/cli/session/result_display.rb"
    cut = Typography.ellipsis(path, 30)

    assert_operator cut.length, :<=, 30
    assert cut.end_with?("…")
  end

  def test_no_budget_means_no_cut
    assert_equal "kept", Typography.ellipsis("kept", 0)
  end

  def test_the_boundary_does_not_abandon_the_line
    # A boundary exists only when it keeps most of the budget; a cut that
    # surrendered half the line would trade honesty for politeness.
    cut = Typography.ellipsis("one two three four five six seven eight", 12)

    assert_operator cut.length, :<=, 12
    assert cut.end_with?("…")
  end
end
