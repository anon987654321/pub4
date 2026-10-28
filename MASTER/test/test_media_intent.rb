# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "shellwords"
require_relative "../lib/io/media_intent"
require_relative "../lib/music/synth"

class MediaIntentTest < Minitest::Test
  LISTING = "Progressions:\n   0  Cm9 Fm9\n\nDrum patterns: dilla_shadow_full, dilla_broken_full, dilla_shadow, dilla_broken, boom_bap, sparse\nGroove profiles: dilla_shadow, dry\n"

  # dilla.rb answers --list with its menu; anything else is a render.
  def dilla_stub(calls)
    lambda do |root:, tool:, arg:, env: {}|
      calls << { root:, tool:, arg:, env: }
      arg == "--list" ? Master::Result.ok(LISTING) : Master::Result.ok("Wrote a render")
    end
  end

  # Renders land in a temporary XDG_DATA_HOME and the player is not started.
  def without_sound
    Dir.mktmpdir do |home|
      saved = ENV.fetch("XDG_DATA_HOME", nil)
      ENV["XDG_DATA_HOME"] = home
      Master::Music::Synth.stub(:play, 4242) { yield }
    ensure
      saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
    end
  end

  def test_literal_postpro_command_accepts_a_directory
    Dir.mktmpdir do |root|
      source = File.join(root, "new photos")
      Dir.mkdir(source)
      calls = []

      Master::Io::ScriptDispatch.stub(
        :run,
        lambda do |root:, tool:, arg:, env: {}|
          calls << { root:, tool:, arg:, env: }
          Master::Result.ok("postpro: graded")
        end,
      ) do
        result = Master::Io::MediaIntent.dispatch(
          %(run postpro.rb over "#{source}"),
          root:,
        )

        assert result.ok?, -> { result.message.to_s }
      end

      assert_equal 1, calls.size
      assert_equal "postpro", calls.first[:tool]
      assert_equal [source], Shellwords.split(calls.first[:arg])
      assert_equal root, calls.first[:root]
    end
  end

  def test_natural_postpro_language_extracts_intent_and_entities
    parsed = Master::Io::NaturalIntent.resolve(
      "run postpro over the latest 3 jpg photos in my Downloads folder",
    )

    refute_nil parsed
    assert_equal :postprocess, parsed.intent
    assert_operator parsed.confidence, :>=, 0.9
    assert_equal "latest", parsed.entities[:recency]
    assert_equal 3, parsed.entities[:count]
    assert_equal "downloads", parsed.entities[:location]
    assert_equal "jpeg", parsed.entities[:file_type]
    assert_equal "photo", parsed.entities[:object]
  end

  def test_natural_media_intent_does_not_read_digits_from_a_path_as_a_count
    parsed = Master::Io::NaturalIntent.resolve(
      'run postpro over "/tmp/master-media-12345/new photos"',
    )

    refute_nil parsed
    assert_equal :postprocess, parsed.intent
    assert_nil parsed.entities[:count]
    assert_equal "photo", parsed.entities[:object]
  end

  def test_natural_postpro_language_defaults_recent_selection_when_count_is_omitted
    Dir.mktmpdir do |source|
      6.times do |index|
        path = File.join(source, "photo#{index}.jpg")
        File.write(path, "")
        File.utime(Time.now - (index * 10), Time.now - (index * 10), path)
      end

      selection = Master::Io::MediaIntent.send(
        :postpro_selection,
        "edit the latest photos",
        source,
      )

      assert_equal 5, selection[:files].size
      assert_equal File.join(source, "photo0.jpg"), selection[:files].first
    end
  end

  def test_plain_live_music_language_routes_to_dilla
    assert Master::Io::MediaIntent.handles?("play some music in real time")
    assert Master::Io::MediaIntent.handles?("play some music locally")
    calls = []

    without_sound do
      Master::Io::ScriptDispatch.stub(:run, dilla_stub(calls)) do
        result = Master::Io::MediaIntent.dispatch("play some music locally", root: MasterPaths.root)
        assert result.ok?, -> { result.message.to_s }
      end
    end

    assert_equal %w[dilla dilla], calls.map { |call| call[:tool] }
    assert_equal "--list", calls.first[:arg]
  end

  def test_bare_play_renders_the_curated_blue_hour_showcase_and_plays_the_wav
    calls = []
    result = nil

    without_sound do
      Master::Io::ScriptDispatch.stub(:run, dilla_stub(calls)) do
        result = Master::Io::MediaIntent.play_live_music("", root: MasterPaths.root)
        assert result.ok?, -> { result.message.to_s }
        assert_match(/\.wav\z/, result.value![:path])
      end
    end

    words = Shellwords.split(calls.fetch(0)[:arg])
    assert_includes words, "--showcase"
    assert_includes words, "--no-video"
    assert_equal "Blue Hour — Dilla Minor Dub Cut", result.value!.fetch(:style)
    assert_equal "dilla_shadow_full", result.value!.fetch(:drums)
    assert_equal "kit_dust", result.value!.fetch(:kit)
    refute_includes words, "--list"
    assert_match(/blue-hour-\d{8}T\d{6}Z(?:-\d+)?\.wav\z/, words[words.index("--out") + 1])
  end

  def test_postpro_capability_question_does_not_require_source_path
    result = Master::Io::MediaIntent.dispatch("can you use postpro.rb?", root: MasterPaths.root)

    assert result.ok?, -> { result.message.to_s }
    assert_match(/provide an existing image file or directory path/, result.value!.fetch(:rendered))
  end

  def test_background_music_is_a_media_intent
    assert Master::Io::MediaIntent.handles?("play your music in the background")
    calls = []
    without_sound do
      Master::Io::ScriptDispatch.stub(:run, dilla_stub(calls)) do
        result = Master::Io::MediaIntent.dispatch("play your music in the background", root: MasterPaths.root)
        assert result.ok?
      end
    end
    assert_equal "dilla", calls.first[:tool]
    assert_equal "--list", calls.first[:arg]
  end

  def test_desktop_postpro_variations_keep_the_desktop_source
    Dir.mktmpdir("master-home") do |home|
      desktop = File.join(home, "Desktop")
      Dir.mkdir(desktop)
      previous_home = ENV["HOME"]
      ENV["HOME"] = home
      calls = []

      Master::Io::ScriptDispatch.stub(
        :run,
        lambda do |root:, tool:, arg:, env: {}|
          calls << { root:, tool:, arg:, env: }
          Master::Result.ok("postpro: varied")
        end,
      ) do
        result = Master::Io::MediaIntent.dispatch(
          "run 5 random extreme postpro.rb variations of the new images in my local Desktop folder",
          root: home,
        )
        assert result.ok?, -> { result.message.to_s }
      end

      assert_equal [desktop, "--random", "--count", "5", "--rough"], Shellwords.split(calls.fetch(0).fetch(:arg))
    ensure
      ENV["HOME"] = previous_home
    end
  end

  def test_absolute_image_glob_dispatches_without_truncating_the_path
    Dir.mktmpdir("master-desktop") do |dir|
      2.times { |index| File.write(File.join(dir, "new#{index}.jpg"), "fixture") }
      calls = []

      Master::Io::ScriptDispatch.stub(
        :run,
        lambda do |root:, tool:, arg:, env: {}|
          calls << { root:, tool:, arg:, env: }
          Master::Result.ok("postpro: varied")
        end,
      ) do
        pattern = File.join(dir, "*.jpg")
        result = Master::Io::MediaIntent.dispatch(
          "run 5 random extreme postpro.rb variations of #{pattern}",
        )
        assert result.ok?, -> { result.message.to_s }
      end

      assert_equal "postpro", calls.fetch(0).fetch(:tool)
      assert_equal [dir, "--random", "--count", "5", "--rough"],
                   Shellwords.split(calls.fetch(0).fetch(:arg))
    end
  end

  def test_postpro_literal_is_a_media_intent
    assert Master::Io::MediaIntent.handles?("run postpro.rb over ~/Pictures/new")
    assert Master::Io::MediaIntent.handles?("use postpro for these photos in ~/Pictures/new")
    refute Master::Io::MediaIntent.handles?("what is postpro?")
  end
end
