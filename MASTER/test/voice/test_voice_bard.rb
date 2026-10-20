# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceBard < Minitest::Test
  Narrator = Master::Voice::Narrator
  CONFIG = Narrator.load_config(:bard).merge("poll_s" => 0.01).freeze

  def build(reply: nil, env: {})
    @now = 100.0
    @spoken = []
    writer = reply ? ->(**) { reply } : ->(**) { raise Narrator::LaneWriter::Unavailable, "no lane" }
    Narrator.new(voice: :bard, config: CONFIG, writer:, speaker: ->(sentence) { @spoken << sentence },
                 backlog: -> { 0 }, audible: -> { true }, clock: -> { @now }, env:)
  end

  def beat(bard, event)
    bard.observe(event)
    @now += CONFIG.fetch("batch_window_s") + 0.1
    bard.tick
  end

  def spoken_include?(pattern) = @spoken.any? { |sentence| sentence.match?(pattern) }

  def test_the_bard_is_on_by_default_over_the_narrators_knobs
    assert_equal true, CONFIG["enabled"]
    assert_equal Narrator.load_config["max_tokens"], CONFIG["max_tokens"], "unset knobs come from the narrator"
  end

  def test_the_bard_has_its_own_dry_voice_without_changing_the_narrator
    assert_equal "davis", CONFIG["voice"]
    assert_equal "-10%", CONFIG["rate"]
    assert_equal "-14Hz", CONFIG["pitch"]
    refute_equal CONFIG["voice"], Narrator.load_config["voice"]
  end

  def test_the_script_lays_the_bard_over_the_narration_filters
    script = Narrator::Script.load(*Narrator.script_paths(:bard))

    assert_includes script.register_words, "song"
    assert_nil script.template(:opening, 0, "reading 14 files"), "the bard keeps no written lines"
    assert script.closing?("fix0: complete, 2 repairs"), "the narration closing patterns still apply"
    assert script.ignored?("tts0: speaking"), "the narration ignore patterns still apply"
  end

  def test_it_is_silent_when_no_lane_is_live_rather_than_reading_a_filler
    assert_equal :rate, beat(build, "scan0: reading 14 files")
    assert_empty @spoken
  end

  def test_a_reply_that_invents_something_is_not_spoken
    { "The scan found 47 mysterious modules in the dark." => "an invented number",
      "Everything is complete and verified." => "an unsupported outcome",
      "The ancient engines hummed under a silver moon." => "no anchor in the events" }.each do |reply, why|
      @spoken = []
      beat(build(reply:), "scan0: 3 files checked")

      assert_empty @spoken, "#{reply} (#{why})"
    end
  end

  def test_a_slam_line_that_names_the_events_may_use_new_words
    beat(build(reply: "Three files checked, and the pocket stays warm."), "scan0: 3 files checked")

    assert_equal ["Three files checked, and the pocket stays warm."], @spoken
  end

  def test_a_lyrical_sentence_that_uses_only_the_events_and_the_register_survives
    beat(build(reply: "The song checks the files."), "scan0: 3 files checked")

    assert_equal ["The song checks the files."], @spoken
  end

  def test_either_switch_in_the_environment_silences_it
    assert_equal :off, build(env: { "MASTER_BARD" => "0" }).tick
    assert_equal :off, build(env: { "MASTER_NARRATE" => "0" }).tick
  end
end

# Which teller speaks: the bard when it is on, the plain narrator when it is off, nobody when both are.
class TestVoiceTellerChoice < Minitest::Test
  Narrator = Master::Voice::Narrator

  def teller_with_both_audible
    bard = Narrator.instance(:bard)
    plain = Narrator.instance
    bard.stub(:audible?, true) { plain.stub(:audible?, true) { return Narrator.teller } }
  end

  def test_the_bard_speaks_when_both_are_on_and_the_narrator_when_it_is_off
    Narrator.reset_instance!
    Narrator.instance(:bard).enable!
    Narrator.instance.enable!

    assert_same Narrator.instance(:bard), teller_with_both_audible

    Narrator.instance(:bard).disable!

    assert_same Narrator.instance, teller_with_both_audible
  ensure
    Narrator.reset_instance!
  end

  def test_nobody_tells_the_story_when_both_are_off
    Narrator.reset_instance!
    Narrator.instance(:bard).disable!
    Narrator.instance.disable!

    assert_nil Narrator.teller
    assert_equal false, Narrator.observe("scan0: reading 14 files")
  ensure
    Narrator.reset_instance!
  end
end
