# frozen_string_literal: true

require_relative "test_helper"

# tts.lang is one flag per utterance, so a sentence that switches between
# Norwegian and English goes through one pronunciation model. Detection is
# per phrase; whether it is acted on is a policy flag, because acting on it
# means a second voice and data/voice.yml locks one.
class TestPhraseLanguage < Minitest::Test
  L = Master::Voice::Language
  M = Master::Voice::Melody
  T = Master::Voice::Transcendent

  def test_a_norwegian_only_letter_is_decisive_on_its_own
    assert_equal :nb, L.detect("Vi må se på det")
    assert_equal :nb, L.detect("Løsningen er ferdig")
  end

  def test_a_marker_is_enough_without_a_special_letter
    assert_equal :nb, L.detect("Det ser faktisk riktig ut")
    assert_equal :nb, L.detect("Jeg tror ikke det")
  end

  # The threshold is one, so the list earns it by excluding every Norwegian word
  # that is also English. These are the ones that would otherwise drag an
  # English clause across.
  def test_words_that_are_both_norwegian_and_english_are_not_markers
    assert_equal :en, L.detect("The problem is in the event bridge")
    assert_equal :en, L.detect("Wait for the deploy to finish")
    assert_equal :en, L.detect("It can restart on its own")
    assert_equal :en, L.detect("This is the de facto layout")
    assert_equal :en, L.detect("Open the file in vi")
    assert_equal :en, L.detect("A man under the sin of it")
  end

  def test_english_is_the_default_for_anything_uncertain
    assert_equal :en, L.detect("")
    assert_equal :en, L.detect("relayd 8080")
  end

  def test_a_mixed_reply_splits_into_phrases_of_different_languages
    text = "Det ser faktisk riktig ut. The problem is in the event bridge."
    emotion = Master::Voice::Emotion.analyze(text)
    plan = M.plan(text, emotion, melodic: false, languages: { nb: :finn })

    assert_equal 2, plan[:phrases].length
    assert_equal :finn, plan[:phrases][0][:voice]
    assert_nil plan[:phrases][1][:voice], "an unmapped language inherits the resolved voice"
  end

  def test_no_language_map_means_no_voice_on_any_phrase
    text = "Det ser faktisk riktig ut. The problem is in the event bridge."
    emotion = Master::Voice::Emotion.analyze(text)
    plan = M.plan(text, emotion, melodic: false, languages: nil)

    assert(plan[:phrases].none? { |p| p.key?(:voice) })
  end

  # data/voice.yml sets single_voice: osman and persona_affects_text_only: true.
  # Switching voices mid-utterance is the one thing that contradicts it, so it
  # ships off and the default has to stay that way until it is chosen.
  def test_switching_is_off_by_default_so_the_single_voice_policy_holds
    refute T::DEFAULTS["phrase_language_switching"]
    assert_nil T.phrase_languages(T::DEFAULTS)
  end

  def test_turning_it_on_maps_only_the_languages_that_name_a_voice
    cfg = T::DEFAULTS.merge("phrase_language_switching" => true)

    assert_equal({ nb: :finn }, T.phrase_languages(cfg))
  end

  def test_the_mapped_voice_is_one_the_registry_actually_knows
    T::DEFAULTS["phrase_language_voices"].each_value do |key|
      next if key.to_s.empty?

      assert Master::Voice::Speech::VOICES.key?(key.to_sym), "#{key} is not a registered voice"
    end
  end
end
