# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/boot/paths"
require_relative "../lib/io/media_intent"

class MediaIntentSpec < Minitest::Test
  MediaIntent = Master::Io::MediaIntent

  # ScriptDispatch.run hits real tools, so the routing tests swap it out the way
  # Ruby itself does a singleton. minitest's stub is not available on this box.
  def with_dispatch_stub(runner)
    klass = Master::Io::ScriptDispatch
    orig = klass.method(:run)
    klass.define_singleton_method(:run) { |**kwargs| runner.call(**kwargs) }
    yield
  ensure
    klass.define_singleton_method(:run, orig)
  end

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

      with_dispatch_stub(runner) do
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
    with_dispatch_stub(runner) do
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
    with_dispatch_stub(runner) do
      result = MediaIntent.dispatch("make me a beat")
      assert result.ok?
    end
    assert_equal "dilla", captured[:tool]
    # engine CLI is `dilla.rb dilla <output> <bars>` -- no --style/--output/generate flags
    assert_match(/\Adilla\s+\S+\s+\d+\z/, captured[:arg])
    assert_equal "dilla", captured[:env]["RENDER_MODE"]
    refute captured[:env].key?("TRACK"), "plain 'dilla' style should not force TRACK, letting the engine pick its own default progression"
  end

  def test_routes_explicit_image_requests_to_replicate
    captured = nil
    runner = lambda do |**kwargs|
      captured = kwargs
      Master::Result.ok("rendered")
    end

    with_dispatch_stub(runner) do
      result = MediaIntent.dispatch("generate a photo of Bergen at the fjord")
      assert result.ok?
      assert_equal :replicate, result.value![:media]
    end

    assert_equal "replicate", captured[:tool]
    assert_includes captured[:arg], "--prompt generate\\ a\\ photo\\ of\\ Bergen\\ at\\ the\\ fjord"
  end

  def with_fake_bus
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, payload| events << [event, payload] }
    [bus, events]
  end

  def test_play_live_music_defaults_to_the_dilla_showcase
    captured = nil
    runner = lambda do |**kwargs|
      captured = kwargs
      Master::Result.ok("live showcase started")
    end

    with_dispatch_stub(runner) do
      result = MediaIntent.play_live_music("")
      assert result.ok?
    end

    assert_equal "dilla", captured[:tool]
    assert_equal "live showcase", captured[:arg]
  end

  def test_play_live_music_normalizes_the_five_named_artist_lanes
    calls = []
    runner = lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("live artist started")
    end

    with_dispatch_stub(runner) do
      %w[bach dilla madlib flylo royksopp].each do |artist|
        assert MediaIntent.play_live_music(artist).ok?, artist
      end
    end

    assert_equal 5, calls.size
    assert_equal %w[live play bach live play dilla live play madlib live play flylo live play royksopp],
                 calls.map { |call| call[:arg].split(" ") }.flatten
  end

  def test_background_music_publishes_the_named_artist_to_the_bus
    bus, events = with_fake_bus
    runner = ->(**_kwargs) { Master::Result.ok("live default started") }

    with_dispatch_stub(runner) do
      result = MediaIntent.play_background_music("play some royksopp in the background", bus: bus)
      assert result.ok?
    end
    assert_equal [["client_action", { action: "dilla_bg", artist: "royksopp" }]], events
  end

  def test_background_music_publishes_a_bare_toggle_without_an_artist
    bus, events = with_fake_bus
    runner = ->(**_kwargs) { Master::Result.ok("live default started") }

    with_dispatch_stub(runner) do
      assert MediaIntent.play_background_music("play some background music", bus: bus).ok?
    end
    assert_equal [["client_action", { action: "dilla_bg" }]], events
  end

  def test_live_stop_publishes_the_browser_stop
    bus, events = with_fake_bus
    # Voice::Playback may be undefined in this test process; stop_live_audio
    # guards it with defined?. The stub only has to answer ScriptDispatch.run.
    runner = ->(**_kwargs) { Master::Result.ok("stopped") }

    with_dispatch_stub(runner) do
      result = MediaIntent.stop_live_audio(bus: bus)
      assert result.ok?
    end
    assert_equal [["client_action", { action: "dilla_bg", stop: true }]], events
  end
end
