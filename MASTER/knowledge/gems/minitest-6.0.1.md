# frozen_string_literal: true

require "minitest/autorun"

# Minimal implementation to satisfy the test suite.
# Provides two whimsical methods used by the tests.
class MemeThing
  # Returns a playful greeting.
  #
  # @return [String] the greeting
  def i_can_has_cheezburger?
    "OHAI!"
  end

  # Returns an enthusiastic affirmation.
  #
  # @return [String] the affirmation
  def will_it_blend?
    "YES!"
  end
end

class MemeTest < Minitest::Test
  def setup
    @meme = MemeThing.new
  end

  def test_cheezburger
    assert_equal "OHAI!", @meme.i_can_has_cheezburger?
  end

  def test_blend_is_positive
    # Ensure the response is not a negative answer.
    refute_match(/^no/i, @meme.will_it_blend?)
  end

  def test_skip_example
    skip "Skipping this test deliberately"
  end
end