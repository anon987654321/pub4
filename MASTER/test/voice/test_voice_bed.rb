# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class TestVoiceBed < Minitest::Test
  Bed = Master::Voice::Bed

  def config = Master::Voice::Narrator.load_config(:bard).fetch("bed")

  def test_the_bed_is_on_by_default_and_draws_one_listed_progression
    assert_equal true, config["enabled"]

    argv = Bed.live_command(config, random: Random.new(1))

    assert_includes config["progressions"].map(&:to_s), argv[argv.index("--progression") + 1]
  end

  def test_two_starts_need_not_play_the_same_song
    argvs = Array.new(6) { |n| Bed.live_command(config, random: Random.new(n)) }
    seeds = argvs.map { |argv| argv[argv.index("--seed") + 1] }

    assert_operator seeds.uniq.size, :>, 1
  end

  def test_the_player_carries_the_volume_from_the_data
    assert_includes Bed.player(config), "volume=#{config["volume"]}"
  end

  def test_a_cached_track_plays_once_through_so_the_next_progression_can_follow
    Dir.mktmpdir do |dir|
      track = File.join(dir, "bed one.wav")
      File.write(track, "RIFF")
      argv = Bed.loop_command(config, track)

      assert_equal "ffplay", argv.first
      assert_includes argv, "-autoexit"
      refute_includes argv, "-loop"
      assert_equal track, argv.last
    end
  end

  def test_the_cache_is_read_from_the_configured_directory
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.wav"), "RIFF")
      File.write(File.join(dir, "empty.wav"), "")
      settings = config.merge("cache_dir" => dir)

      assert_equal [File.join(dir, "a.wav")], Bed.tracks(settings)
      assert_equal File.join(dir, "a.wav"), Bed.cached(settings)
    end
  end

  def test_the_next_track_is_never_the_one_just_played
    pool = %w[a b c].map { |name| "/cache/#{name}.wav" }
    Bed.stub(:tracks, pool) do
      assert(Array.new(30) { Bed.next_track(config, "/cache/a.wav") }.none? { |track| track == "/cache/a.wav" })
    end
  end

  def test_a_full_cache_renders_nothing_more
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.wav"), "RIFF")

      assert_equal false, Bed.prerender(config.merge("cache_dir" => dir, "cache_target" => 1))
    end
  end

  def test_there_is_no_music_at_startup_unless_the_data_says_so
    assert_equal false, config["autostart"]
    assert_equal false, Bed.boot(nil)
    assert_equal false, Bed.boot(config.merge("autostart" => false))
  end

  def test_a_disabled_or_missing_bed_never_starts
    assert_equal false, Bed.start(nil)
    assert_equal false, Bed.start(config.merge("enabled" => false))
    refute_predicate Bed, :running?
  end
end
