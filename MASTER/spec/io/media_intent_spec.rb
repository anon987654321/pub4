# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/boot/paths"
require_relative "../../lib/io/media_intent"

class MediaIntentSpec < Minitest::Test
  MediaIntent = Master::Io::MediaIntent

  def test_recognizes_explicit_image_requests
    assert MediaIntent.handles?("generate a photo of Bergen at the fjord")
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

      Master::Io::ScriptDispatch.stub(:run, runner) do
        result = MediaIntent.dispatch(%(give "#{source}" a VHS tape look))
        assert result.ok?
      end
      assert_equal "postpro", captured[:tool]
      assert_includes captured[:arg], "vhs_tape"
    end
  end

  def test_routes_bach_and_flylo_to_distinct_full_track_styles
    calls = []
    runner = lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("rendered")
    end
    Master::Io::ScriptDispatch.stub(:run, runner) do
      assert MediaIntent.dispatch("create a Bach-inspired instrumental").ok?
      assert MediaIntent.dispatch("make a Flying Lotus beat").ok?
    end
    assert(calls.any? { |c| c[:env]&.fetch("TRACK", nil) == "baroque" })
    assert(calls.any? { |c| c[:env]&.fetch("TRACK", nil) == "flylo" })
  end

  def test_generate_beat_invokes_the_dilla_cli_verb_not_the_removed_wrapper_flags
    captured = nil
    runner = lambda do |**kwargs|
      captured = kwargs
      Master::Result.ok("rendered")
    end
    Master::Io::ScriptDispatch.stub(:run, runner) do
      result = MediaIntent.dispatch("make me a beat")
      assert result.ok?
    end
    assert_equal "dilla", captured[:tool]
    # engine CLI is `dilla.rb dilla <output> <bars>` -- no --style/--output/generate flags
    assert_match(/\Adilla\s+\S+\s+\d+\z/, captured[:arg])
    assert_equal "dilla", captured[:env]["RENDER_MODE"]
    refute captured[:env].key?("TRACK"), "plain 'dilla' style should not force TRACK, letting the engine pick its own default progression"
  end

  def test_routes_explicit_image_requests_to_repligen
    captured = nil
    runner = lambda do |**kwargs|
      captured = kwargs
      Master::Result.ok("rendered")
    end

    Master::Io::ScriptDispatch.stub(:run, runner) do
      result = MediaIntent.dispatch("generate a photo of Bergen at the fjord")
      assert result.ok?
      assert_equal :repligen, result.value![:media]
    end

    assert_equal "repligen", captured[:tool]
    assert_includes captured[:arg], "--prompt generate\\ a\\ photo\\ of\\ Bergen\\ at\\ the\\ fjord"
  end
end
