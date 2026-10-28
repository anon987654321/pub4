# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/io/media_intent"
require_relative "../lib/music/synth"

class MediaIntentSpec < Minitest::Test
  MediaIntent = Master::Io::MediaIntent

  # Reference profiles and renders live under XDG_DATA_HOME; every test gets its own so the
  # operator's saved active style never steers a routing assertion.
  def setup
    @saved_xdg = ENV["XDG_DATA_HOME"]
    @xdg = Dir.mktmpdir("media-intent-xdg")
    ENV["XDG_DATA_HOME"] = @xdg
  end

  def teardown
    @saved_xdg ? ENV["XDG_DATA_HOME"] = @saved_xdg : ENV.delete("XDG_DATA_HOME")
    FileUtils.rm_rf(@xdg)
  end

  # ScriptDispatch.run hits real tools, so the routing tests swap it out.
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
  DILLA_LISTING = LISTING.sub(
    "Drum patterns: boom_bap, offbeat_inversion, sparse",
    "Drum patterns: dilla_shadow_full, dilla_broken_full, dilla_shadow, dilla_broken, dusty_laid_back, boom_bap, offbeat_inversion, sparse",
  ).sub(
    "Groove profiles: late_snare, behind_the_beat, dry",
    "Groove profiles: dilla_shadow, late_snare, behind_the_beat, dry",
  )

  # Answers --list with the menu and records every other call; a render "writes" its --out.
  def dilla_runner(calls, listing: LISTING)
    lambda do |**kwargs|
      calls << kwargs
      next Master::Result.ok(listing) if kwargs[:arg] == "--list"

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
        assert_equal 1, calls.size
        assert_equal "dilla", calls.first[:tool]
        words = Shellwords.split(calls.first[:arg])
        assert_includes words, "--showcase"
        assert_includes words, "--no-video"
        assert_match(/blue-hour-\d{8}T\d{6}Z(?:-\d+)?\.wav\z/, words[words.index("--out") + 1])
      end
    end
  end

  def test_dilla_render_paths_add_suffixes_instead_of_reusing_existing_takes
    Dir.mktmpdir do |home|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = home
      at = Time.utc(2026, 10, 19, 12, 34, 56)
      first = MediaIntent.dilla_unique_render_path("blue-hour", at:)
      FileUtils.mkdir_p(File.dirname(first))
      File.write(first, "preserve")
      second = MediaIntent.dilla_unique_render_path("blue-hour", at:)

      assert_equal "blue-hour-20261019T123456Z.wav", File.basename(first)
      assert_equal "blue-hour-20261019T123456Z-1.wav", File.basename(second)
      assert_equal "preserve", File.read(first)
    ensure
      saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
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

  def test_play_live_music_honours_a_bare_progression_number
    Dir.mktmpdir do |dir|
      with_clean_player do
        calls = []
        ENV["XDG_DATA_HOME"], saved = dir, ENV["XDG_DATA_HOME"]
        begin
          with_player do
            with_dispatch_stub(dilla_runner(calls)) { assert MediaIntent.play_live_music("1 sparse").ok? }
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

  def test_play_list_names_the_choices_and_plays_nothing
    with_clean_player do
      with_player do |played|
        calls = []
        with_dispatch_stub(dilla_runner(calls)) do
          %w[list --list].each do |word|
            result = MediaIntent.play_live_music(word)
            assert result.ok?, result.inspect
            assert_match(/progressions \d+\.\.\d+/, result.value![:rendered])
            assert_includes result.value![:rendered], "sparse"
          end
        end
        assert_empty played
        assert_equal ["--list"], calls.map { |call| call[:arg] }.uniq
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
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      request = "use yt-dlp and demucs to grab, split up, and analyze https://youtu.be/mx9NU4LmDwM?si=example12345"
      assert MediaIntent.handles?(request)
      refute MediaIntent.handles?("I liked the music inside that YouTube video")
      refute MediaIntent.handles?("this music video looks interesting https://youtu.be/mx9NU4LmDwM")
      refute MediaIntent.handles?("nice track: https://youtu.be/mx9NU4LmDwM")

      calls = []
      begin
        with_dispatch_stub(lambda do |**kwargs|
          calls << kwargs
          Master::Result.ok("reference0: analyzed audio")
        end) do
          result = MediaIntent.dispatch(request, root: "/tmp/pub4")
          assert result.ok?, result.inspect
          assert_equal :audio_reference_analysis, result.value!.fetch(:media)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end

      assert_equal 1, calls.size
      assert_equal "dilla", calls.first.fetch(:tool)
      argv = Shellwords.split(calls.first.fetch(:arg))
      assert_equal "reference", argv.first
      assert_equal "https://youtu.be/mx9NU4LmDwM?si=example12345", argv[1]
    end
  end

  def test_a_bare_youtube_link_is_treated_as_an_audio_reference
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      url = "https://youtu.be/mx9NU4LmDwM?si=barelink"
      urls = [url, "#{url}."]
      calls = []
      begin
        with_dispatch_stub(lambda do |**kwargs|
          calls << kwargs
          Master::Result.ok("reference0: analyzed audio")
        end) do
          urls.each do |candidate|
            assert MediaIntent.handles?(candidate)
            result = MediaIntent.dispatch(candidate, root: "/tmp/pub4")
            assert result.ok?, result.inspect
            assert_equal :audio_reference_analysis, result.value!.fetch(:media)
          end
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      assert_equal 2, calls.size
      calls.each do |call|
        argv = Shellwords.split(call.fetch(:arg))
        assert_equal ["reference", url], argv
      end
    end
  end

  def test_multiple_youtube_links_in_one_message_share_the_style_hint
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      urls = [
        "https://youtu.be/mx9NU4LmDwM?si=first",
        "https://youtu.be/abcdefghijk?si=second",
      ]
      calls = []
      begin
        with_dispatch_stub(lambda do |**kwargs|
          calls << kwargs
          Master::Result.ok("reference0: analyzed audio")
        end) do
          request = "learn the J Dilla sound from these tracks: #{urls.join(' and ')}"
          assert MediaIntent.handles?(request)
          result = MediaIntent.dispatch(request, root: "/tmp/pub4")
          assert result.ok?, result.inspect
          assert_equal :audio_reference_analysis, result.value!.fetch(:media)
          assert_equal "j_dilla", result.value!.fetch(:style)
          assert_equal 2, result.value!.fetch(:source_count)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      assert_equal 2, calls.size
      calls.each_with_index do |call, index|
        argv = Shellwords.split(call.fetch(:arg))
        assert_equal "reference", argv.first
        assert_equal urls[index], argv[1]
        assert_equal "j_dilla", argv[argv.index("--style") + 1]
      end
    end
  end

  def test_reference_batch_limit_fails_closed_before_running_tools
    ids = %w[aaaaaaaaaaa bbbbbbbbbbb ccccccccccc ddddddddddd eeeeeeeeeee fffffffffff]
    request = "study these techno tracks: #{ids.map { |id| "https://youtu.be/#{id}" }.join(' and ')}"
    calls = []
    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("unexpected reference analysis")
    end) do
      result = MediaIntent.dispatch(request, root: "/tmp/pub4")
      refute result.ok?
    end
    assert_empty calls
  end

  def test_short_and_embedded_youtube_links_are_audio_references
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      urls = [
        "https://m.youtube.com/shorts/mx9NU4LmDwM",
        "https://music.youtube.com/watch?v=mx9NU4LmDwM",
        "https://www.youtube.com/watch?feature=shared&v=mx9NU4LmDwM",
        "https://www.youtube.com/embed/mx9NU4LmDwM",
      ]
      begin
        with_dispatch_stub(lambda do |**kwargs|
          Master::Result.ok("reference0: analyzed audio")
        end) do
          urls.each do |url|
            result = MediaIntent.dispatch(url, root: "/tmp/pub4")
            assert result.ok?, "#{url}: #{result.inspect}"
            assert_equal :audio_reference_analysis, result.value!.fetch(:media)
          end
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
    end
  end

  def test_explicit_general_reference_does_not_inherit_the_active_style
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      root = File.join(dir, "dilla-references")
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "active_style.json"), JSON.generate("style_key" => "j_dilla"))
      File.write(File.join(root, "latest_profile.json"), JSON.generate("style_key" => "j_dilla"))
      calls = []
      begin
        with_dispatch_stub(lambda do |**kwargs|
          calls << kwargs
          Master::Result.ok("reference0: analyzed audio")
        end) do
          url = "https://youtu.be/mx9NU4LmDwM?si=general"
          result = MediaIntent.dispatch("analyze this as a neutral reference: #{url}", root: dir)
          assert result.ok?, result.inspect
          assert_equal "general", result.value!.fetch(:style)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      argv = Shellwords.split(calls.fetch(0).fetch(:arg))
      assert_equal ["reference", "https://youtu.be/mx9NU4LmDwM?si=general"], argv
    end
  end

  def test_active_style_survives_a_general_latest_reference
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      root = File.join(dir, "dilla-references")
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "active_style.json"), JSON.generate("style_key" => "j_dilla"))
      File.write(File.join(root, "latest_profile.json"), JSON.generate("style_key" => "general"))
      begin
        assert_equal "j_dilla", MediaIntent.active_reference_style
        assert_equal "j_dilla", MediaIntent.reference_style_for("here is another song https://youtu.be/mx9NU4LmDwM")
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
    end
  end

  def test_consecutive_reference_links_inherit_the_last_explicit_style
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      FileUtils.mkdir_p(File.join(dir, "dilla-references"))
      File.write(File.join(dir, "dilla-references", "latest_profile.json"), JSON.generate("style_key" => "j_dilla"))
      calls = []
      begin
        with_dispatch_stub(lambda do |**kwargs|
          calls << kwargs
          Master::Result.ok("reference0: analyzed audio")
        end) do
          result = MediaIntent.dispatch("here's another track: https://youtu.be/mx9NU4LmDwM?si=next", root: "/tmp/pub4")
          assert result.ok?, result.inspect
          assert_equal "j_dilla", result.value!.fetch(:style)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      argv = Shellwords.split(calls.fetch(0).fetch(:arg))
      assert_equal "j_dilla", argv[argv.index("--style") + 1]
    end
  end

  def test_a_j_dilla_reference_is_explicitly_tagged_for_the_analyzer
    url = "https://youtu.be/mx9NU4LmDwM?si=dilla"
    calls = []
    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("reference0: analyzed audio")
    end) do
      result = MediaIntent.dispatch("study this J Dilla track so you learn its sound: #{url}", root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal "j_dilla", result.value!.fetch(:style)
    end
    argv = Shellwords.split(calls.fetch(0).fetch(:arg))
    assert_equal "reference", argv.first
    assert_equal "j_dilla", argv[argv.index("--style") + 1]
  end

  def test_generic_make_a_beat_like_this_analyzes_the_link_before_rendering
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      url = "https://youtu.be/mx9NU4LmDwM?si=generic"
      calls = []
      render_stub = MediaIntent.method(:render_dilla)
      MediaIntent.define_singleton_method(:render_dilla) do |text, root:, output: nil|
        render_stub.call(text, root:, output: output && File.join(dir, File.basename(output)))
      end
      begin
        with_dispatch_stub(dilla_runner(calls)) do
          result = MediaIntent.dispatch("make a beat like this #{url}", root: dir)
          assert result.ok?, result.inspect
          assert_equal :dilla, result.value!.fetch(:media)
        end
      ensure
        MediaIntent.define_singleton_method(:render_dilla, render_stub)
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end

      assert_equal "dilla", calls.first.fetch(:tool)
      first_argv = Shellwords.split(calls.first.fetch(:arg))
      assert_equal "reference", first_argv.first
      assert_equal url, first_argv[1]
      assert_equal "--list", calls[1].fetch(:arg)
      assert_equal "dilla", calls.last.fetch(:tool)
      assert_match(/--out/, calls.last.fetch(:arg))
    end
  end

  def test_a_reference_and_generation_request_analyzes_then_renders
    url = "https://youtu.be/mx9NU4LmDwM?si=techno"
    calls = []
    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok(kwargs[:arg].start_with?("reference ") ? "reference0: analyzed audio" : "dilla0: rendered")
    end) do
      result = MediaIntent.dispatch("create an industrial techno track like this #{url}", root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal :industrial_techno, result.value!.fetch(:media)
    end
    assert_equal 2, calls.size
    analysis = Shellwords.split(calls.first.fetch(:arg))
    assert_equal "industrial_techno", analysis[analysis.index("--style") + 1]
    assert_equal "industrial-techno", Shellwords.split(calls.last.fetch(:arg)).first
  end

  def test_a_j_dilla_reference_can_be_analyzed_and_rendered_in_one_request
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      url = "https://youtu.be/mx9NU4LmDwM?si=dilla"
      calls = []
      render_stub = MediaIntent.method(:render_dilla)
      MediaIntent.define_singleton_method(:render_dilla) do |text, root:, output: nil|
        render_stub.call(text, root:, output: output && File.join(dir, File.basename(output)))
      end
      begin
        with_dispatch_stub(lambda do |**kwargs|
          calls << kwargs
          next Master::Result.ok(DILLA_LISTING) if kwargs[:arg] == "--list"

          Master::Result.ok(kwargs[:arg].start_with?("reference ") ? "reference0: analyzed audio" : "dilla0: rendered")
        end) do
          result = MediaIntent.dispatch("make a J Dilla beat like this #{url}", root: dir)
          assert result.ok?, result.inspect
          assert_equal :dilla, result.value!.fetch(:media)
        end
      ensure
        MediaIntent.define_singleton_method(:render_dilla, render_stub)
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end

      assert_equal 3, calls.size
      analysis = Shellwords.split(calls.first.fetch(:arg))
      assert_equal "reference", analysis.first
      assert_equal "j_dilla", analysis[analysis.index("--style") + 1]
      render = Shellwords.split(calls.last.fetch(:arg))
      assert_equal "dilla", calls.last.fetch(:tool)
      assert_equal "kit_dust", render[render.index("--kit") + 1]
      assert_equal "rhodes_mark1", render[render.index("--voice") + 1]
      assert_equal "dilla_shadow_full", render[render.index("--drums") + 1]
    end
  end

  def test_explicit_j_dilla_followup_overrides_an_active_techno_reference
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      reference_root = File.join(dir, "dilla-references")
      FileUtils.mkdir_p(reference_root)
      File.write(File.join(reference_root, "latest_profile.json"), JSON.generate("style_key" => "industrial_techno"))
      File.write(File.join(reference_root, "active_style.json"), JSON.generate("style_key" => "industrial_techno"))
      calls = []
      begin
        with_dispatch_stub(dilla_runner(calls)) do
          result = MediaIntent.dispatch("make a J Dilla beat like that", root: dir)
          assert result.ok?, result.inspect
          assert_equal :dilla, result.value!.fetch(:media)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      render = calls.find { |call| call[:arg] != "--list" }
      assert render
      words = Shellwords.split(render.fetch(:arg))
      assert_equal "kit_dust", words[words.index("--kit") + 1]
      assert_equal "dilla", render.fetch(:tool)
    end
  end

  def test_explicit_techno_followup_overrides_a_general_reference
    calls = []
    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("dilla0: rendered")
    end) do
      result = MediaIntent.dispatch("make a techno track like that", root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal :industrial_techno, result.value!.fetch(:media)
    end
    assert_equal "industrial-techno", Shellwords.split(calls.fetch(0).fetch(:arg)).first
  end

  def test_followup_generation_uses_the_most_recent_industrial_reference
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      FileUtils.mkdir_p(File.join(dir, "dilla-references"))
      File.write(File.join(dir, "dilla-references", "latest_profile.json"), JSON.generate("style_key" => "industrial_techno"))
      calls = []
      begin
        with_dispatch_stub(lambda do |**kwargs|
          calls << kwargs
          Master::Result.ok("dilla0: rendered")
        end) do
          result = MediaIntent.dispatch("make a track like that", root: "/tmp/pub4")
          assert result.ok?, result.inspect
          assert_equal :industrial_techno, result.value!.fetch(:media)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      assert_equal "industrial-techno", Shellwords.split(calls.fetch(0).fetch(:arg)).first
    end
  end

  def test_inactive_j_dilla_profile_does_not_steer_a_generic_beat
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      root = File.join(dir, "dilla-references")
      FileUtils.mkdir_p(File.join(root, "profiles", "j_dilla"))
      File.write(File.join(root, "active_style.json"), JSON.generate("style_key" => "industrial_techno"))
      File.write(File.join(root, "latest_profile.json"), JSON.generate("style_key" => "industrial_techno"))
      File.write(File.join(root, "profiles", "j_dilla", "latest_profile.json"), JSON.generate(
        "style_key" => "j_dilla", "target_bpm" => 92, "groove_profile" => "dilla_shadow",
      ))
      calls = []
      begin
        with_dispatch_stub(dilla_runner(calls)) do
          result = MediaIntent.render_dilla("make a beat", root: dir)
          assert result.ok?, result.inspect
          assert_nil result.value!.fetch(:kit)
          assert_nil result.value!.fetch(:groove)
          assert_nil result.value!.fetch(:bpm)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      words = Shellwords.split(calls.last.fetch(:arg))
      refute_includes words, "--kit"
      refute_includes words, "--profile"
      refute_includes words, "--bpm"
    end
  end

  def test_a_saved_j_dilla_reference_steers_tempo_and_groove
    Dir.mktmpdir do |dir|
      saved = ENV["XDG_DATA_HOME"]
      ENV["XDG_DATA_HOME"] = dir
      reference_root = File.join(dir, "dilla-references")
      FileUtils.mkdir_p(File.join(reference_root, "profiles", "j_dilla"))
      profile = JSON.generate(
        "style_key" => "j_dilla", "target_bpm" => 92, "groove_profile" => "behind_the_beat",
        "features" => {
          "drums_energy_share" => 0.5, "other_energy_share" => 0.375,
          "timing_spread_ms" => 20.0, "onset_density_per_bar" => 15.0, "offbeat_onset_share" => 0.7
        }
      )
      File.write(File.join(reference_root, "latest_profile.json"), profile)
      File.write(File.join(reference_root, "profiles", "j_dilla", "latest_profile.json"), profile)
      File.write(File.join(reference_root, "active_style.json"), JSON.generate("style_key" => "j_dilla"))
      calls = []
      begin
        with_dispatch_stub(dilla_runner(calls, listing: DILLA_LISTING)) do
          result = MediaIntent.render_dilla("make a beat", root: dir)
          assert result.ok?, result.inspect
          assert_equal "behind_the_beat", result.value!.fetch(:groove)
          assert_equal 92, result.value!.fetch(:bpm)
          assert_equal "dilla_broken_full", result.value!.fetch(:drums)
          assert_equal 1.14, result.value!.fetch(:groove_scale)
        end
      ensure
        saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
      end
      words = Shellwords.split(calls.last.fetch(:arg))
      assert_equal "behind_the_beat", words[words.index("--profile") + 1]
      assert_equal "92", words[words.index("--bpm") + 1]
      assert_equal "dilla_broken_full", words[words.index("--drums") + 1]
      assert_equal "1.14", words[words.index("--groove") + 1]
      assert_equal "kit_dust", words[words.index("--kit") + 1]
      assert_equal "rhodes_mark1", words[words.index("--voice") + 1]
      assert_equal "dilla_night", words[words.index("--effect-rig") + 1]
      assert_equal "subtle", words[words.index("--sonitex") + 1]
      assert_equal "2", words[words.index("--sonitex-instances") + 1]
      assert_equal "0.54", words[words.index("--vcs") + 1]
      assert_equal "2.0", words[words.index("--drum-balance") + 1]
      assert_equal "1.0", words[words.index("--chord-balance") + 1]
    end
  end

  def test_plain_techno_request_uses_the_techno_renderer
    calls = []
    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("dilla0: wrote original industrial techno")
    end) do
      result = MediaIntent.dispatch("make a techno track", root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal :industrial_techno, result.value!.fetch(:media)
    end
    assert_equal "industrial-techno", Shellwords.split(calls.fetch(0).fetch(:arg)).first
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

  def test_fantastic_volume_two_reference_is_tagged_as_dilla_and_allows_album_length
    url = "https://youtu.be/XgObDlzrlUc?si=album-reference"
    request = "study Slum Village Fantastic, Vol. 2 as an album reference: #{url}"
    calls = []

    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("reference0: analyzed audio")
    end) do
      result = MediaIntent.dispatch(request, root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal :audio_reference_analysis, result.value!.fetch(:media)
      assert_equal "j_dilla", result.value!.fetch(:style)
    end

    argv = Shellwords.split(calls.fetch(0).fetch(:arg))
    assert_equal "reference", argv.first
    assert_equal url, argv[1]
    assert_equal "7200", argv[argv.index("--max-duration") + 1]
    assert_equal "j_dilla", argv[argv.index("--style") + 1]
  end

  def test_slum_village_reference_infers_the_dilla_production_profile
    url = "https://youtu.be/XgObDlzrlUc?si=slum-village"
    calls = []

    with_dispatch_stub(lambda do |**kwargs|
      calls << kwargs
      Master::Result.ok("reference0: analyzed audio")
    end) do
      result = MediaIntent.dispatch("study this Slum Village track: #{url}", root: "/tmp/pub4")
      assert result.ok?, result.inspect
      assert_equal "j_dilla", result.value!.fetch(:style)
    end

    argv = Shellwords.split(calls.fetch(0).fetch(:arg))
    assert_equal "j_dilla", argv[argv.index("--style") + 1]
  end
end
