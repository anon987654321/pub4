# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceBed < Minitest::Test
  Bed = Master::Voice::Bed

  def config = Master::Voice::Narrator.load_config(:bard).fetch("bed")

  def test_the_bed_is_on_by_default_and_draws_one_listed_progression
    assert_equal true, config["enabled"]

    argv = Bed.command(config, random: Random.new(1))

    assert_includes config["progressions"].map(&:to_s), argv[argv.index("--progression") + 1]
  end

  def test_two_starts_need_not_play_the_same_song
    argvs = Array.new(6) { |n| Bed.command(config, random: Random.new(n)) }
    seeds = argvs.map { |argv| argv[argv.index("--seed") + 1] }

    assert_operator seeds.uniq.size, :>, 1
  end

  def test_the_player_carries_the_volume_from_the_data
    assert_includes Bed.player(config), "volume=#{config["volume"]}"
  end

  def test_a_disabled_or_missing_bed_never_starts
    assert_equal false, Bed.start(nil)
    assert_equal false, Bed.start(config.merge("enabled" => false))
    refute_predicate Bed, :running?
  end
end
