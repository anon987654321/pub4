# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class TestVoiceBed < Minitest::Test
  Bed = Master::Voice::Bed

  def config = Master::Voice::Narrator.load_config(:bard).fetch("bed")

  def teardown
    Bed.stop
  end

  def test_the_bed_uses_dilla_chords_and_the_existing_heavy_effects
    assert_equal true, config["enabled"]
    assert_equal true, config["autostart"]
    assert_equal false, config["live"]
    assert_equal [1, 7, 8, 9, 15], config["progressions"]
    assert_equal 0.22, config["volume"]
    assert_match(/dilla-chords\z/, config["cache_dir"])
    args = config["render_args"]
    assert_includes args, "--no-video"
    assert_includes args, "dilla_night"
    assert_includes args, "rhodes_mark1"
    assert_includes args, "soft_swing"
    assert_includes args, "--echo=1,2,3"
    assert_includes args, "subtle"
    refute_includes args, "ambient"
    refute_includes args, "--drums"
  end

  def test_two_renders_need_not_sound_the_same
    seeds = Array.new(6) { |n| Bed.pick_args(config, Random.new(n)).last }

    assert_operator seeds.uniq.size, :>, 1
  end

  def test_a_cached_track_plays_once_through_so_the_next_can_follow
    Dir.mktmpdir do |dir|
      track = File.join(dir, "bed one.wav")
      File.write(track, "RIFF")
      argv = Bed.loop_command(config, track)

      assert_equal "ffplay", argv.first
      assert_includes argv, "-autoexit"
      assert_includes argv.join(" "), "volume=#{config["volume"]}"
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

  def test_an_empty_cache_waits_for_a_render_instead_of_streaming_music
    Bed.stub(:prerender, true) do
      Bed.stub(:sleep, nil) do
        assert_nil Bed.play_next(config.merge("cache_dir" => Dir.mktmpdir), nil)
      end
    end
  end

  def test_the_bard_releasing_the_bed_leaves_the_held_ambient_playing
    Bed.stub(:start, true) { Bed.boot(config) }
    assert_predicate Bed, :held?
    Bed.stub(:stop, -> { flunk "a held bed was stopped" }) { Bed.release }

    Bed.stop
    stopped = false
    Bed.stub(:stop, -> { stopped = true }) { Bed.release }
    assert stopped
  end

  def test_the_held_ambient_does_not_keep_the_face_from_listening
    Bed.stub(:start, true) { Bed.boot(config) }
    Bed.stub(:running?, true) { refute_predicate Bed, :foreground? }

    Bed.stop
    Bed.stub(:running?, true) { assert_predicate Bed, :foreground? }
  end

  def test_a_missing_or_switched_off_bed_never_boots
    Bed.boot(nil)
    refute_predicate Bed, :held?
    Bed.boot(config.merge("autostart" => false))
    refute_predicate Bed, :held?
  end

  def test_a_disabled_or_missing_bed_never_starts
    assert_equal false, Bed.start(config), "the suite sets MASTER_BED=0, so an enabled bed stays silent"
    assert_equal false, Bed.start(nil)
    assert_equal false, Bed.start(config.merge("enabled" => false))
    refute_predicate Bed, :running?
  end
end
