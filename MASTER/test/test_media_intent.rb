# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "shellwords"
require_relative "lib/io/media_intent"

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

  def test_postpro_literal_is_a_media_intent
    assert Master::Io::MediaIntent.handles?("run postpro.rb over ~/Pictures/new")
    assert Master::Io::MediaIntent.handles?("use postpro for these photos in ~/Pictures/new")
    refute Master::Io::MediaIntent.handles?("what is postpro?")
  end
end
