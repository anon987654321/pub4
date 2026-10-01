# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "shellwords"
require_relative "../lib/io/media_intent"

class MediaIntentTest < Minitest::Test
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
        end
      ) do
        result = Master::Io::MediaIntent.dispatch(
          %(run postpro.rb over "#{source}"),
          root:
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
      "run postpro over the latest 3 jpg photos in my Downloads folder"
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
      'run postpro over "/tmp/master-media-12345/new photos"'
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
        source
      )

      assert_equal 5, selection[:files].size
      assert_equal File.join(source, "photo0.jpg"), selection[:files].first
    end
  end

  def test_background_music_is_a_media_intent
    assert Master::Io::MediaIntent.handles?("play your music in the background")
    calls = []
    Master::Io::ScriptDispatch.stub(
      :run,
      lambda do |root:, tool:, arg:, env: {}|
        calls << { root:, tool:, arg:, env: }
        Master::Result.ok("playing Dilla background")
      end
    ) do
      result = Master::Io::MediaIntent.dispatch("play your music in the background", root: MasterPaths.root)
      assert result.ok?
    end
    assert_equal "dilla", calls.first[:tool]
    assert_equal "live default", calls.first[:arg]
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
        end
      ) do
        result = Master::Io::MediaIntent.dispatch(
          "run 5 random extreme postpro.rb variations of the new images in my local Desktop folder",
          root: home
        )
        assert result.ok?, -> { result.message.to_s }
      end

      assert_equal [desktop, "--random", "--count", "5", "--rough"], Shellwords.split(calls.fetch(0).fetch(:arg))
    ensure
      ENV["HOME"] = previous_home
    end
  end

  def test_postpro_literal_is_a_media_intent
    assert Master::Io::MediaIntent.handles?("run postpro.rb over ~/Pictures/new")
    assert Master::Io::MediaIntent.handles?("use postpro for these photos in ~/Pictures/new")
    refute Master::Io::MediaIntent.handles?("what is postpro?")
  end
end
