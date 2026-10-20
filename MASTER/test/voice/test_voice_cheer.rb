# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceCheer < Minitest::Test
  Narrator = Master::Voice::Narrator

  def cheer_config = Master.load_yaml(Master.data_path("bard.yml")).fetch("cheer")

  def script = Narrator::Script.load(*Narrator.script_paths(:bard))

  def build(reply: nil)
    @now = 1_000.0
    @spoken = []
    writer = reply ? ->(**) { reply } : ->(**) { raise Narrator::LaneWriter::Unavailable, "no lane" }
    config = Narrator.load_config(:bard).merge("poll_s" => 0.01)
    Narrator.new(voice: :bard, config:, writer:, speaker: ->(line) { @spoken << line },
                 backlog: -> { 0 }, audible: -> { true }, clock: -> { @now })
  end

  def test_it_is_on_by_default_and_speaks_only_after_the_idle_wait
    bard = build

    assert_equal true, cheer_config["enabled"]
    assert_equal :wait, bard.tick

    @now += cheer_config["after_s"] + 1

    assert_equal :spoken, bard.tick
    assert_includes cheer_config["lines"].join(" "), @spoken.first[0, 12]
  end

  def test_a_model_freestyle_is_spoken_when_it_makes_no_claim
    bard = build(reply: "Quiet room, loose shoulders, soft clocks, easy rocks.")
    @now += cheer_config["after_s"] + 1
    bard.tick

    assert_equal ["Quiet room, loose shoulders, soft clocks, easy rocks."], @spoken
  end

  def test_a_freestyle_that_claims_an_outcome_or_a_number_is_replaced_by_a_written_line
    ["Everything is fixed and verified, rest easy.", "Forty tests passed, take a bow."].each do |reply|
      bard = build(reply:)
      @spoken.clear
      @now += cheer_config["after_s"] + 1
      bard.tick

      refute_match(/fixed|verified|forty|passed/i, @spoken.join(" "), reply)
      refute_empty @spoken
    end
  end

  def test_written_lines_rotate_before_any_repeats
    bard = build
    lines = Array.new(cheer_config["lines"].size) do
      @now += cheer_config["after_s"] + 1
      bard.tick
      @spoken.last
    end

    assert_equal lines.size, lines.uniq.size
  end

  def test_the_plain_narrator_never_freestyles
    @now = 1_000.0
    plain = Narrator.new(config: Narrator.load_config.merge("poll_s" => 0.01), backlog: -> { 0 },
                         audible: -> { true }, clock: -> { @now }, speaker: ->(line) { @spoken = [line] })
    @now += 10_000

    assert_equal :wait, plain.tick
  end
end
