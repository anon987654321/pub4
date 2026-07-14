# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/master_paths"
require_relative "../../lib/reach/media_intent"

class MediaIntentSpec < Minitest::Test
  MediaIntent = Master::Reach::MediaIntent

  def test_recognizes_explicit_local_identity_image_requests
    assert MediaIntent.handles?("generate a photo of the LoRA model Ragnhild at the fjord")
  end

  def test_recognizes_original_beat_requests_without_a_slash_command
    assert MediaIntent.handles?("make me a Flying Lotus beat")
    assert MediaIntent.handles?("create a Bach-inspired instrumental")
  end

  def test_recognizes_an_explicit_post_processing_request
    assert MediaIntent.handles?("give /tmp/source.jpg a VHS look")
    assert MediaIntent.handles?("give /tmp/source.jpg a CRT broadcast look")
    assert MediaIntent.handles?("give /tmp/source.jpg a camcorder glitch look")
  end

  def test_does_not_hijack_ordinary_artist_discussion
    refute MediaIntent.handles?("why did J Dilla use loose timing?")
  end

  def test_routes_vhs_requests_to_the_vhs_tape_preset
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source image.jpg")
      File.write(source, "fixture")
      captured = nil
      runner = lambda do |**kwargs|
        captured = kwargs
        Master::Result.ok("processed")
      end

      Master::Reach::ScriptDispatch.stub(:run, runner) do
        result = MediaIntent.dispatch(%(give "#{source}" a VHS tape look))
        assert result.ok?
      end
      assert_equal "postpro", captured[:tool]
      assert_includes captured[:arg], "vhs_tape"
    end
  end

  def test_routes_bach_and_flylo_to_distinct_full_track_styles
    styles = []
    runner = lambda do |**kwargs|
      styles << kwargs[:arg]
      Master::Result.ok("rendered")
    end
    Master::Reach::ScriptDispatch.stub(:run, runner) do
      assert MediaIntent.dispatch("create a Bach-inspired instrumental").ok?
      assert MediaIntent.dispatch("make a Flying Lotus beat").ok?
    end
    assert styles.any? { |args| args.include?("--style baroque") }
    assert styles.any? { |args| args.include?("--style flylo") }
  end
end
