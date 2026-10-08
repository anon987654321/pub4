# frozen_string_literal: true

require_relative "test_helper"
require "voice/strunk_pass"

class TestStrunkPassLanguage < Minitest::Test
  def test_norwegian_hedges_are_removed
    output = Master::Voice::StrunkPass.brevity("Jeg tror dette virker som en muligens god løsning.", language: :nb)
    refute_match(/jeg tror|virker som|muligens/i, output)
  end

  def test_english_hedges_remain_separate_from_norwegian
    output = Master::Voice::StrunkPass.brevity("I think that this would work.", language: :en)
    refute_match(/I think that|would/i, output)
    assert_match(/this work/i, output)
  end

  def test_language_is_detected_when_not_supplied
    output = Master::Voice::StrunkPass.brevity("Dette virker som en mulig løsning.")
    refute_match(/virker som/i, output)
  end
end
