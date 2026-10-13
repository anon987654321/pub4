# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/boot/paths"
require_relative "../lib/io/media_intent"
require_relative "../lib/music/synth"

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

  LISTING = <<~TEXT
      Progressions:
         0  Cm9 Fm9 Bbm9 Ebmaj9
         1  Dm7 G7 Cmaj7 Fmaj7

      Drum patterns: boom_bap, offbeat_inversion, sparse
      Groove profiles: late_snare, behind_the_beat, dry
  TEXT

  # Answers --list with the menu and records every other call; a render "writes" its --out.
  def dilla_runner(calls)
    lambda do |**kwargs|
      calls << kwargs
      next Master::Result.ok(LISTING) if kwargs[:arg] == "--list"

      out = Shellwords.split(kwargs[:arg].to_s).each_cons(2).find { |flag, _| flag == "--out" }&.last
      File.write(out, "RIFF") if out
      Master::Result.ok("Wrote #{out}")
    end
  end

  def with_player(pid: 4242)
    played = []
    synth = Master::Music::Synth
    original = synth.method(:play)
    synth.define_singleton_method(:play) { |path, **| played << path; pid }
    yield played
  ensure
    synth.define_singleton_method(:play, original)
  end

  def with_clean_player
    MediaIntent.instance_variable_set(:@player_pid, nil)
    yield
  ensure
    MediaIntent.instance_variable_set(:@player_pid, nil)
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

def test_a_beat_request_renders_a_progression_with_a_drum_pattern_to_a_wav
  Dir.mktmpdir do |home|
    calls = []
    with_dispatch_stub(dilla_runner(calls)) do
      stub = MediaIntent.method(:render_dilla)
      MediaIntent.define_singleton_method(:render_dilla) { |text, root:, output: nil| stub.call(text, root:, output: output && File.join(home, File.basename(output))) }
      begin
        result = MediaIntent.dispatch("make me a Flying Lotus beat")
        assert result.ok?
        assert_equal :dilla, result.value![:media]
      ensure
        MediaIntent.define_singleton_method(:render_dilla, stub)
      end
    end
    assert_equal ["--list"], [calls.first[:arg]]
    render = calls.last
    assert_equal "dilla", render[:tool]
    words = Shellwords.split(render[:arg])
    assert_includes %w[0 1], words[words.index("--progression") + 1]
    assert_includes %w[boom_bap offbeat_inversion sparse], words[words.index("--drums") + 1]
    assert_match(/\.wav\z/, words[words.index("--out") + 1])
  end
end

def test_a_beat_request_that_names_a_progression_and_a_pattern_gets_them
  Dir.mktmpdir do |dir|
    calls = []
    with_dispatch_stub(dilla_runner(calls)) do
      result = MediaIntent.render_dilla("make a progression 1 beat on offbeat_inversion", root: dir, output: File.join(dir, "x.wav"))
      assert result.ok?
    end
    words = Shellwords.split(calls.last[:arg])
    assert_equal %w[--progression 1 --out], [words[0], words[1], words[2]]
    assert_equal "offbeat_inversion", words[words.index("--drums") + 1]
  end
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

def test_play_live_music_renders_then_plays_the_wav
  Dir.mktmpdir do |dir|
    with_clean_player do
      calls = []
      ENV["XDG_DATA_HOME"], saved = dir, ENV["XDG_DATA_HOME"]
      begin
        with_player do |played|
          with_dispatch_stub(dilla_runner(calls)) do
            result = MediaIntent.play_live_music("")
            assert result.ok?, result.inspect
            assert_equal :dilla_live, result.value![:media]
            assert_equal [result.value![:path]], played
            assert_match(%r{/dilla-renders/\d{4}-\d{2}-\d{2}/.+\.wav\z}, played.first)
          end
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      assert_equal "--list", calls.first[:arg]
      assert_equal "dilla", calls.last[:tool]
      assert_includes calls.last[:arg], "--progression"
    end
  end
end

def test_play_live_music_honours_a_named_progression_and_pattern
  Dir.mktmpdir do |dir|
    with_clean_player do
      calls = []
      ENV["XDG_DATA_HOME"], saved = dir, ENV["XDG_DATA_HOME"]
      begin
        with_player do
          with_dispatch_stub(dilla_runner(calls)) { assert MediaIntent.play_live_music("progression 1 sparse").ok? }
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      words = Shellwords.split(calls.last[:arg])
      assert_equal "1", words[words.index("--progression") + 1]
      assert_equal "sparse", words[words.index("--drums") + 1]
    end
  end
end

def test_play_live_music_reports_a_failed_render_without_playing
  with_clean_player do
    with_player do |played|
      failing = lambda do |**kwargs|
        kwargs[:arg] == "--list" ? Master::Result.ok(LISTING) : Master::Result.err("dilla: exit=1")
      end
      with_dispatch_stub(failing) { refute MediaIntent.play_live_music("").ok? }
      assert_empty played
    end
  end
end

def test_background_music_publishes_the_named_artist_to_the_bus
  bus, events = with_fake_bus
  with_clean_player do
    with_player do
      with_dispatch_stub(dilla_runner([])) do
        assert MediaIntent.play_background_music("play some royksopp in the background", bus:).ok?
      end
    end
  end
  assert_equal [["client_action", { action: "dilla_bg", artist: "royksopp" }]], events
end

def test_background_music_publishes_a_bare_toggle_without_an_artist
  bus, events = with_fake_bus
  with_clean_player do
    with_player do
      with_dispatch_stub(dilla_runner([])) { assert MediaIntent.play_background_music("play some background music", bus:).ok? }
    end
  end
  assert_equal [["client_action", { action: "dilla_bg" }]], events
end

  def test_live_stop_publishes_the_browser_stop_and_says_when_nothing_plays
    bus, events = with_fake_bus
    with_clean_player do
      result = MediaIntent.stop_live_audio(bus:)
      assert result.ok?
      assert_equal "nothing is playing", result.value![:rendered]
    end
    assert_equal [["client_action", { action: "dilla_bg", stop: true }]], events
  end

  def test_live_stop_ends_the_player_it_started
    bus, = with_fake_bus
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30")
    with_clean_player do
      MediaIntent.instance_variable_set(:@player_pid, child)
      assert_equal child, MediaIntent.player_pid
      assert_match(/stopped the Dilla player/, MediaIntent.stop_live_audio(bus:).value![:rendered])
      assert_nil MediaIntent.player_pid
    end
    Process.wait(child)
  end

  def test_reference_audio_request_dispatches_audio_only_to_dilla
    request = "use yt-dlp and demucs to grab, split up, and analyze https://youtu.be/mx9NU4LmDwM?si=example12345"
    assert MediaIntent.handles?(request)
    refute MediaIntent.handles?("I liked the music inside that YouTube video")

    calls = []
    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("reference0: analyzed audio")
    end) do
      result = MediaIntent.dispatch(request, root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal :audio_reference_analysis, result.value!.fetch(:media)
    end

    assert_equal 1, calls.size
    assert_equal "dilla", calls.first.fetch(:tool)
    argv = Shellwords.split(calls.first.fetch(:arg))
    assert_equal "reference", argv.first
    assert_equal "https://youtu.be/mx9NU4LmDwM?si=example12345", argv[1]
  end

  def test_industrial_techno_request_leaves_arrangement_and_seed_to_dilla
    calls = []
    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("dilla0: wrote original industrial techno")
    end) do
      result = MediaIntent.dispatch("make an industrial techno track", root: "/tmp/pub4")
      assert result.ok?, result.inspect
    end

    assert_equal "dilla", calls.first.fetch(:tool)
    argv = Shellwords.split(calls.first.fetch(:arg))
    assert_equal "industrial-techno", argv.first
    refute_includes argv, "--bars"
    refute_includes argv, "--seed"
  end

  def test_industrial_techno_request_routes_with_explicit_tempo_and_bars
    request = "create an industrial techno track at 142 BPM for 12 bars"
    assert MediaIntent.handles?(request)
    calls = []

    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("dilla0: wrote original industrial techno")
    end) do
      result = MediaIntent.dispatch(request, root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal :industrial_techno, result.value!.fetch(:media)
    end

    argv = Shellwords.split(calls.fetch(0).fetch(:arg))
    assert_equal "dilla", calls.first.fetch(:tool)
    assert_equal "industrial-techno", argv.first
    assert_equal "142", argv[argv.index("--bpm") + 1]
    assert_equal "12", argv[argv.index("--bars") + 1]
  end

end
