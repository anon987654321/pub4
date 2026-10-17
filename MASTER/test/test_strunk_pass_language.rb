# frozen_string_literal: true

require_relative "test_helper"
require "voice/strunk_pass"

class TestStrunkPassLanguage < Minitest::Test
  def test_norwegian_filter_removes_only_leading_padding
    output = Master::Voice::StrunkPass.brevity("Jeg tror dette virker som en muligens god løsning.", language: :nb)
    refute_match(/\Ajeg tror/i, output)
    assert_match(/virker som/i, output)
    assert_match(/muligens/i, output)
  end

  def test_english_filter_preserves_meaning_bearing_modal_verbs
    output = Master::Voice::StrunkPass.brevity("I think that this would work. The scan could not finish.", language: :en)
    refute_match(/\AI think that/i, output)
    assert_match(/this would work/i, output)
    assert_match(/scan could not finish/i, output)
  end

  def test_cached_rules_follow_same_second_voice_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "voice.yml")
      File.write(path, "voice:\n  strunk:\n    preambles:\n      - first\n")

      pass = Master::Voice::StrunkPass.new
      Master.stub(:data_path, path) do
        assert_includes pass.send(:rules).fetch("preambles"), "first"

        stat = File.stat(path)
        File.write(path, "voice:\n  strunk:\n    preambles:\n      - second\n")
        File.utime(stat.atime, stat.mtime, path)

        assert_equal ["second"], pass.send(:rules).fetch("preambles")
      end
    end
  end

  def test_language_is_detected_without_deleting_a_mid_sentence_qualifier
    output = Master::Voice::StrunkPass.brevity("Dette virker som en mulig løsning.")
    assert_match(/virker som/i, output)
  end
end
