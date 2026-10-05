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

  def test_cached_rules_follow_same_second_voice_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "voice.yml")
      original = Master.data_path("voice.yml")
      source = File.read(original, encoding: "UTF-8")
      replacement = source.sub(/(strunk:.*\n(?:.*\n){0,8}?preambles:\n)(\s*-\s*["'][^"']*["']\n)/, "\\1          - \"ONLY_THIS_TEST\"\n")

      File.write(path, replacement)
      pass = Master::Voice::StrunkPass.new
      pass.define_singleton_method(:rules) do
        data = Master.load_yaml(path) || {}
        data.dig("voice", "strunk") || {}
      end
      assert_equal true, pass.brevity("ONLY_THIS_TEST hello").include?("ONLY_THIS_TEST")
    end
  end

  def test_language_is_detected_when_not_supplied
    output = Master::Voice::StrunkPass.brevity("Dette virker som en mulig løsning.")
    refute_match(/virker som/i, output)
  end
end
