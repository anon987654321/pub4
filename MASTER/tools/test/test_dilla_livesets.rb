# frozen_string_literal: true

require_relative "dilla_helper"
require_relative "../dilla/lib/livesets"
require "open3"
require "fileutils"

# The livesets' choices, read without playing a pass: exec is stubbed wherever a
# pass would start, so nothing reaches ffmpeg or a speaker.
class TestDillaLivesets < Minitest::Test
  def with_env(pairs)
    saved = pairs.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    pairs.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  # Stubs a Livesets function for the block and puts the real one back after.
  # Removing a stub is not enough: module_function defines each function on the
  # singleton, so removing the stub removes the function for every later test.
  def stubbing(stubs)
    singleton = Livesets.singleton_class
    originals = stubs.keys.to_h { |name| [name, singleton.method_defined?(name) && singleton.instance_method(name)] }
    stubs.each { |name, body| Livesets.define_singleton_method(name, &body) }
    yield
  ensure
    originals.each do |name, original|
      singleton.remove_method(name)
      singleton.define_method(name, original) if original
    end
  end

  # The one take kept through `recall keep` before renders/ went. Its journal
  # row is what recall reads, so the seed has to reach the set it names with
  # the kit and the progression it played, not whatever is exported today.
  def test_the_kept_take_recalls_from_the_journal
    handed = nil
    stubbing(exec: ->(*args) { handed = args }) { Livesets.recall!(["1133818290"]) }
    env, _ruby, _engine, *command = handed

    assert_equal %w[live set chord_based_beats], command
    pins = { "LIVE_SEED" => "1133818290", "LIVE_KIT" => "synth", "LIVE_PROGRESSION" => "lydian_augmented_haze",
             "LIVE_ROOM" => "warm", "LIVE_KIT_CYCLE" => "phrase", "LIVE_WEIGHTS" => "phrase=0.62,kit=2.9,crackle=0.3" }
    assert_equal pins, env.slice(*pins.keys)
    assert_equal ["LIVE_SEED", *Livesets::RECALLED.keys].sort, env.keys.sort, "every choice is set from the take or unset"
    assert_nil env.fetch("LIVE_BED"), "a choice the take never made is unset, not inherited"
  end

  # A pin replaces what the seed drew and nothing after it: the draw still
  # happens, so the tempo and the drums a replay rolls next are the same rolls.
  def test_a_pinned_progression_leaves_the_stream_where_the_draw_left_it
    unpinned = with_env("LIVE_PROGRESSION" => nil) { srand(41) && [Livesets.pick_progression, rand] }
    pinned = with_env("LIVE_PROGRESSION" => "lydian_augmented_haze") { srand(41) && [Livesets.pick_progression, rand] }

    assert_equal :lydian_augmented_haze, pinned.first
    assert_equal unpinned.last, pinned.last
  end

  # Unset, the sampled set plays the downward tables with every ratio held under
  # the drag. LIVE_VOICING=up selects the 08-31 tables and lets a chord climb.
  def test_live_voicing_up_selects_the_upward_tables_and_down_stays_the_default
    down = with_env("LIVE_VOICING" => nil) { Livesets.voicing }
    up = with_env("LIVE_VOICING" => "up") { Livesets.voicing }

    assert_equal "down", down
    assert_equal [Livesets::SAMPLED_VOICINGS, Livesets::SAMPLED_PROGRESSIONS], Livesets::VOICING_TABLES.fetch(down)
    assert_equal [Livesets::UP_VOICINGS, Livesets::UP_PROGRESSIONS], Livesets::VOICING_TABLES.fetch(up)
    drag = 0.94
    assert_equal [drag, drag, drag], Livesets.slice_ratios(3, [0, 4, 14], drag, "down")
    assert_operator Livesets.slice_ratios(3, Livesets::UP_VOICINGS.fetch(:maj9), drag, "up").max, :>, drag
  end

  def test_a_sampled_pass_journals_the_voicing_it_played
    rows = []
    stubs = {
      pick_bed: -> { ["/nonexistent/loop.wav", "bed", 0.5] },
      grid: ->(*) { { raw: 2.0, bars_in_loop: 1, bar: 2.0, beat: 0.5, step: 0.25, sxt: 0.125, bpm: 90.0 } },
      journal!: ->(row) { rows << row },
      play!: ->(*) {},
    }
    stubbing(stubs) do
      %w[up down].each { |choice| with_env("LIVE_VOICING" => choice, "LIVE_SEED" => "5") { Livesets.sampled_based_beats! } }
    end

    assert_equal %w[up down], rows.map { |r| r[:voicing] }
    assert_includes Livesets::UP_PROGRESSIONS, rows.first[:progression]
    assert_includes Livesets::SAMPLED_PROGRESSIONS, rows.last[:progression]
  end

  BED_STUBS = {
    pick_bed: -> { ["/nonexistent/loop.wav", "bed", 0.5] },
    grid: ->(*) { { raw: 2.0, bars_in_loop: 1, bar: 2.0, beat: 0.5, step: 0.25, sxt: 0.125, bpm: 90.0 } },
  }.freeze

  # One pass of a set, stopped at the door of ffmpeg: what it would have played
  # and what it journalled.
  def built(set, env = {})
    passes = []
    rows = []
    stubs = BED_STUBS.merge(journal!: ->(row) { rows << row }, play!: ->(inputs, graph, _) { passes << [inputs, graph] })
    stubbing(stubs) { with_env({ "LIVE_SEED" => "5", "LIVE_KIT" => nil }.merge(env)) { Livesets.play_set!(set) } }
    { inputs: passes.first[0], graph: passes.first[1], row: rows.first }
  end

  def test_every_set_builds_a_graph_ffmpeg_can_read
    Livesets::SETS.each do |set|
      pass = built(set)

      assert_empty Livesets.graph_problems(pass[:inputs], pass[:graph]), set
    end
  end

  # The instrument, checked against the defects it exists for: a trailing comma
  # from a comment in a continuation, a label nobody reads, an unseeded source.
  def test_the_graph_lint_sees_the_defects_it_names
    inputs = ["-f lavfi -i anoisesrc=c=pink:d=1", "-i a.wav"]
    graph = ["[0:a]volume=1,,atrim=0:1[a]", "[1:a]anull[b]", "[a]anull[out]"]
    problems = Livesets.graph_problems(inputs, graph)

    assert_includes problems, "1 empty filter(s) in [0:a]volume=1,,atrim=0:1[a]"
    assert_includes problems, "[b] made but never used"
    assert(problems.any? { |p| p.start_with?("unseeded noise") })
    assert_empty Livesets.graph_problems(["-i a.wav"], ["[0:a]volume='if(between(t,1,2),0.5,1.0)':eval=frame[out]"])
  end

  # PRNG draw order is an interface. A pass is named by its seed, and the seed
  # names the pass only while every draw lands where it did when it was
  # journalled; a rand added above an existing one silently re-rolls every take
  # after it. The kept take's own journal line is the pin: replayed today, the
  # seed has to draw the tempo and the drums it drew on 2026-09-01. A new
  # decision draws from Livesets.stream(tag), never from the pass stream.
  def test_the_kept_take_replays_the_draws_its_journal_recorded
    kept = Livesets.passes.find { |r| r["seed"] == 1_133_818_290 }
    row = built("chord_based_beats", Livesets.recall_env(kept))[:row]

    assert_equal kept["bpm"], row[:bpm]
    assert_equal kept["drums"], JSON.parse(JSON.generate(row[:drums]))
  end

  # anoisesrc defaults to seed=-1, a fresh seed per process, so one unseeded
  # source makes a pinned render unrepeatable while every number it prints
  # agrees. The class, closed by audit rather than instance by instance.
  def test_every_noise_source_in_the_engine_names_its_seed
    unseeded = ->(text) { text.gsub(/#\{[^}]*\}/, "X").scan(/anoisesrc=[^"',;\[\s]+/).grep_v(/seed=/) }

    refute_empty unseeded.call('"anoisesrc=c=pink:d=#{total}:a=0.1"'), "the audit has to see an unseeded source"
    sources = Dir[File.join(__dir__, "..", "dilla", "{dilla.rb,lib/*.rb}")]
    found = sources.flat_map { |path| unseeded.call(File.read(path)).map { |hit| "#{File.basename(path)}: #{hit}" } }

    assert_empty found
  end

  # aloop stopped reproducing at 1.5 million samples and held at 120 000, and
  # nobody knows where between. Every set copies its cycle instead, at any length.
  def test_no_set_loops_its_cycle_with_aloop_at_any_length
    [nil, "12", "1200"].each do |length|
      Livesets::SETS.each do |set|
        pass = built(set, "LIVE_LENGTH" => length)

        refute(pass[:graph].any? { |s| s.include?("aloop") }, "#{set} at #{length}")
        assert_empty Livesets.graph_problems(pass[:inputs], pass[:graph])
        assert_equal length ? length.to_f : { "ambient_pads" => 180 }.fetch(set, 96), pass[:row][:seconds]
      end
    end
  end

  def test_a_length_that_is_not_seconds_is_refused
    assert_raises(SystemExit) { with_env("LIVE_LENGTH" => "long") { Livesets.seconds(96) } }
  end

  # The arms of an A/B differ in the stated knobs and nothing else, and a bed set
  # holds one bed across all three.
  def test_an_ab_plan_differs_only_in_what_it_names
    plan = stubbing(pick_bed: -> { ["/b/loop.wav", "rack_01", 0.5] }) do
      with_env("LIVE_BED" => nil) { Livesets.ab_plan("ambient_pads", %w[24 seed=777 LIVE_ROOM=dry]) }
    end
    base, changed = plan[:arms].values_at("baseline", "changed").map(&:last)

    assert_equal plan[:arms]["baseline"], plan[:arms]["control"]
    assert_equal({ "LIVE_SEED" => "777", "LIVE_LENGTH" => "24.0", "LIVE_BED" => "rack_01" }, base)
    assert_equal base.merge("LIVE_ROOM" => "dry"), changed
    assert_raises(SystemExit) { Livesets.ab_plan("chord_based_beats", %w[16]) }
  end

  # Level first: every arm is trimmed to the baseline's loudness before a band
  # is compared or a window is heard.
  def test_ab_trims_match_every_arm_to_the_baseline
    trims = Livesets.ab_trims("baseline" => { lufs: -16.0 }, "control" => { lufs: -16.4 }, "changed" => { lufs: -13.0 })

    assert_equal({ "baseline" => 0.0, "control" => 0.4, "changed" => -3.0 }, trims)
  end

  # The measurement is read back from ffmpeg's own report: the loudness from the
  # summary, the bands in the order the graph declares its volumedetects, and
  # nothing at all when a band is missing rather than a report short of one.
  def test_an_arm_is_measured_from_one_pass_down_a_pipe
    bands = [4, 5, 6, 7, 8, 9].map.with_index { |n, i| "[Parsed_volumedetect_#{n} @ 0x1] mean_volume: -#{20 + i}.5 dB" }
    report = "[Parsed_ebur128_1 @ 0x2] t: 1 I: -70.0 LUFS\n#{bands.reverse.join("\n")}\n  Summary:\n  Integrated loudness:\n    I:         -14.2 LUFS\n"

    assert_equal({ lufs: -14.2, bands: [-20.5, -21.5, -22.5, -23.5, -24.5, -25.5] }, Livesets.ab_parse(report))
    assert_nil Livesets.ab_parse(report.sub(bands.first, ""))
    assert_includes Livesets.ab_measure_graph, "[m]ebur128=peak=true[loud]"
  end

  def test_the_interleaved_file_alternates_the_arms_at_their_trims
    graph = Livesets.ab_interleave_graph({ "baseline" => 0.0, "changed" => -3.0 }, 14)

    assert_empty Livesets.graph_problems(%w[-i -i], graph)
    assert_equal ["[s0]atrim=0.0:4.0", "[s1]atrim=4.0:8.0", "[s2]atrim=8.0:12.0", "[s3]atrim=12.0:14"],
                 graph.grep(/atrim/).map { |g| g[/\A\[s\d\]atrim=[\d.:]+/] }
    assert_includes graph.grep(/\[s1\]/).join, "volume=-3.0dB"
  end

  def test_every_room_builds_every_set_and_is_journalled
    Livesets::ROOMS.each do |room|
      Livesets::SETS.each do |set|
        pass = built(set, "LIVE_ROOM" => room)

        assert_empty Livesets.graph_problems(pass[:inputs], pass[:graph]), "#{set} in #{room}"
        assert_equal room, pass[:row][:room]
      end
    end
    assert_equal({ room: "warm", sonitex: [12, 11, 12, 10], vcs: 6 }, with_env("LIVE_ROOM" => nil) { Livesets.console_record("chord_based_beats") })
    assert_raises(SystemExit) { with_env("LIVE_ROOM" => "bathroom") { Livesets.room } }
  end

  def pink_level(chain)
    out, = Open3.capture2e("ffmpeg", "-hide_banner", "-nostats", "-f", "lavfi", "-i", "anoisesrc=c=pink:d=3:a=0.3:seed=5",
                           "-af", "aformat=channel_layouts=stereo,#{chain},volumedetect", "-f", "null", "-")
    Float(out[/mean_volume: (\S+) dB/, 1])
  end

  # The level contract, measured: every vcs row lands at VCS_DB whatever its
  # depth and smear, and the dry, blown and tape rooms move a stage's level by
  # no more than 2.5 dB. The master and summed rooms are level-dependent by
  # construction -- stacked 1260s add quantisation noise to a quiet signal, and
  # console_stack's makeup was measured against a hot mix -- so what they do to
  # level is live ab's to trim, not this test's to pin.
  def test_every_vcs_stage_lands_at_its_declared_level_and_rooms_keep_it
    skip "ffmpeg is not installed" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

    base = pink_level("anull")
    vcs_rows = Livesets::CONSOLE.values.flat_map(&:values).flatten(1).select { |kind, _| kind == :vcs }.uniq
    vcs_rows.each do |_, params|
      assert_in_delta Livesets::VCS_DB, pink_level(Livesets.vcs(**params)) - base, 0.75, params.inspect
    end
    %w[chord_based_beats ambient_pads].each do |set|
      warm = with_env("LIVE_ROOM" => "warm") { pink_level(Livesets.console(set, :master)) }
      %w[dry blown tape].each do |room|
        assert_in_delta warm, with_env("LIVE_ROOM" => room) { pink_level(Livesets.console(set, :master)) }, 2.5, "#{set} in #{room}"
      end
    end
  end

  # The kit repeats every bar unless the take was kept with it every phrase, and
  # LIVE_FORM arranges each bus by its engine layer across a fitted form.
  def test_the_kit_cycles_each_bar_and_a_form_arranges_each_bus_by_its_layer
    bar_kit = built("chord_based_beats", "LIVE_KIT_CYCLE" => nil)
    phrase_kit = built("chord_based_beats", "LIVE_KIT_CYCLE" => "phrase")

    assert_includes bar_kit[:graph].grep(/\A\[kit\]apad/).first, "whole_dur=#{bar_kit[:row][:bar_s]}"
    assert_includes phrase_kit[:graph].grep(/\A\[kit\]apad/).first, "whole_dur=#{phrase_kit[:row][:chord_s] * 8}"
    shape = with_env("LIVE_FORM" => "soul_32") { Livesets.arrangement("chord_based_beats", 2.0, 64, []) }
    # soul_32 is intro 4, main 8, build 8, turn 8, outro 4 of 32; over 32 bars
    # of two seconds the intro is bars 0-3, and the arranged intro drops the
    # harmony and the drums.
    assert_equal [[0.0, 0.0], [8.0, 1.0], [24.0, 1.06], [40.0, 1.0], [56.0, 0.85]], shape[:phrase]
    assert_equal [[0.0, 0.0], [8.0, 1.0], [56.0, 0.45]], shape[:kit]
    assert_raises(SystemExit) { with_env("LIVE_FORM" => "polka") { Livesets.form } }
    Livesets::SETS.each do |set|
      pass = built(set, "LIVE_FORM" => "soul_32")
      assert_empty Livesets.graph_problems(pass[:inputs], pass[:graph]), set
      assert_equal "soul_32", pass[:row][:form]
    end
  end

  # A mute keeps the graph and the pass stream and takes the part out; DRUMS=0
  # is the engine's kit switch and mutes the kit here. Weights nudge a balance
  # and are journalled, so a take recalls its own.
  def test_mute_groups_and_weights_steer_a_pass_and_are_journalled
    muted = built("sampled_based_beats", "LIVE_MUTE" => "kit,crackle", "LIVE_WEIGHTS" => "under=0.5")

    assert_equal [[0, 0.0]], with_env("LIVE_MUTE" => "kit") { Livesets.arrangement("chord_based_beats", 2.0, 16, [[0, 1.0]]) }[:kit]
    assert(muted[:graph].any? { |g| g.start_with?("[kit_block]volume='0.0'") })
    assert(muted[:graph].any? { |g| g.include?("volume=0,") && g.end_with?("[crackle]") })
    assert_equal "kit,crackle", muted[:row][:muted]
    assert_equal 0.5, muted[:row][:weights][:under]
    assert_includes muted[:graph].grep(/\[under_arranged\]\[kit_arranged\]amix/).first, "weights=0.3 0.5 3.4"
    assert_equal %w[kit], with_env("LIVE_MUTE" => nil, "DRUMS" => "0") { Livesets.muted }
    assert_raises(SystemExit) { with_env("LIVE_MUTE" => "vocals") { Livesets.muted } }
    assert_raises(SystemExit) { with_env("LIVE_WEIGHTS" => "kit=loud") { Livesets.weights("chord_based_beats") } }
    assert_equal "5", with_env("RENDER_SEED" => nil) { built("ambient_pads") && ENV.fetch("RENDER_SEED") }
    assert_equal 0.9, built("ambient_pads", "LIVE_DRAG" => "0.9")[:row][:drag]
    assert_raises(SystemExit) { with_env("LIVE_DRAG" => "1.2") { Livesets.pinned_drag(0.9) } }
  end

  # The engine's devices, reached: a copy-machine cloud under the pads that
  # never plays above the record, a voice stack on every held slice, the sampled
  # phrase hocketed across the stereo field, and a bus patch when one is named.
  # Each off is the graph the take made before it existed.
  def test_the_engine_devices_are_wired_into_the_sets_and_come_off
    pads = built("ambient_pads")
    sampled = built("sampled_based_beats")

    assert_includes pads[:graph].join(";"), "[under_raw]asplit=4"
    assert(pads[:graph].grep(/asetrate=\d+,aresample/).grep(/cmo/).all? { |g| g[/asetrate=(\d+)/, 1].to_i <= 44_100 })
    assert(pads[:graph].any? { |g| g.match?(/\A\[\d+:a\]asplit=3\[p0v0s0\]/) })
    assert(sampled[:graph].any? { |g| g.include?("pan=stereo|") })
    assert_equal [4, 3, 3], [pads[:row][:copy_machine], pads[:row][:voice_stack], sampled[:row][:hocket]]
    off = built("ambient_pads", "LIVE_COPY_MACHINE" => "0", "LIVE_VOICE_STACK" => "1")
    refute_match(/\[cm0\]|p0v0s0/, off[:graph].join(";"))
    refute_match(/pan=stereo/, built("sampled_based_beats", "LIVE_HOCKET" => "1")[:graph].join(";"))
    patched = built("chord_based_beats", "LIVE_BUS_PATCH" => "phrase")
    assert_includes patched[:graph].grep(/\A\[phrase_block\]/).first, "asendcmd=f="
    [pads, sampled, patched].each { |pass| assert_empty Livesets.graph_problems(pass[:inputs], pass[:graph]) }
    assert_raises(SystemExit) { with_env("LIVE_HOCKET" => "9") { Livesets.knob_int("LIVE_HOCKET", 3, 1..4) } }
  end

  # A knob a set reads and nobody documented is a knob nobody can steer by.
  def test_every_knob_a_set_reads_is_documented_and_recalled_knobs_are_among_them
    source = File.read(File.join(__dir__, "..", "dilla", "lib", "livesets.rb"))
    read = source.scan(/ENV(?:\.fetch)?[\[(]\s*"(LIVE_[A-Z_]+)"|knob_int\("(LIVE_[A-Z_]+)"/).flatten.compact.uniq

    assert_includes read, "LIVE_HOCKET", "the scan has to see a knob read through knob_int"
    assert_empty read - Livesets::KNOB_DOCS.keys
    assert_empty Livesets::RECALLED.keys - Livesets::KNOB_DOCS.keys
  end

  # The queue: a starred rack outranks every score, LIVE_KEY keeps the beds in
  # one key, a skip sends a bed to the back, and a pass names what it owes.
  def test_the_bed_queue_honours_stars_keys_skips_and_credits
    Dir.mktmpdir do |dir|
      %w[high low starred other].each { |slug| FileUtils.mkdir_p(File.join(dir, slug)) && File.write(File.join(dir, slug, "loop.wav"), "") }
      rows = { "high" => { "key" => "A minor", "source_label" => "Record", "rights" => "unlicensed", "url" => "https://youtu.be/x" },
               "low" => { "key" => "C major" }, "starred" => { "key" => "C major" }, "other" => { "key" => "A minor" } }
      stubs = { bed_rows: -> { rows }, worth: -> { { "high" => 0.9, "low" => 0.1, "starred" => 0.05, "other" => 0.5 } },
                worth_doc: -> { { "starred" => ["starred"] } } }
      queue = ->(env = {}) { with_env({ "LIVE_BEDS_DIR" => dir, "LIVE_JOURNAL" => File.join(dir, "j.jsonl") }.merge(env)) { Livesets.bed_queue.map { |b| Livesets.slug_of(b) } } }
      stubbing(stubs) do
        assert_equal %w[starred high other low], queue.call.first(4)
        assert_equal %w[high other], queue.call("LIVE_KEY" => "a minor")
        assert_raises(SystemExit) { queue.call("LIVE_KEY" => "F# lydian") }
        with_env("LIVE_JOURNAL" => File.join(dir, "j.jsonl")) { Livesets.journal!(cue: "skip", bed: "starred") }
        assert_equal "starred", queue.call.last
        assert_equal "Record — unlicensed — https://youtu.be/x", Livesets.credit("high")
        assert_nil Livesets.credit("low")
      end
    end
  end

  # A fetch that fails still leaves the URL it was fetching: the record comes
  # before the audio, so nothing it describes can outlive it.
  def test_a_fetched_record_names_its_url_before_the_audio_arrives
    Dir.mktmpdir do |dir|
      out = File.join(dir, "source.wav")
      define_singleton_method(:require_tools!) { |*| nil }
      define_singleton_method(:sh!) { |*| raise "offline" }
      assert_raises(RuntimeError) { download_track("https://youtu.be/abc", out) }

      assert_equal "https://youtu.be/abc", JSON.parse(File.read("#{out}.source.json"))["url"]
    end
  end

  # Playing, not running: a tempo tapped or pinned, a transport that says where
  # the pass is and what changes next, and a Ctrl-C that lets the pass end.
  def test_a_pass_takes_a_tapped_tempo_shows_its_transport_and_stops_when_asked
    assert_equal 120.0, Livesets.tap_bpm([0.0, 0.5, 1.0, 1.9, 2.4])
    assert_nil Livesets.tap_bpm([0.0, 0.5])
    assert_equal 140.0, built("chord_based_beats", "LIVE_BPM" => "140")[:row][:bpm]
    assert_raises(SystemExit) { with_env("LIVE_BPM" => "fast") { Livesets.pinned_bpm } }
    Dir.mktmpdir do |dir|
      bed = File.join(dir, "loop.wav")
      system("ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "5.2", bed)
      skip "ffmpeg is not installed" unless File.file?(bed)
      # 5.2 seconds is 46, 92 or 185 bpm at one, two or four bars.
      assert_equal 2, with_env("LIVE_BPM" => nil) { Livesets.grid(bed, 1.0) }[:bars_in_loop]
      assert_equal 1, with_env("LIVE_BPM" => "46") { Livesets.grid(bed, 1.0) }[:bars_in_loop]
      assert_equal 4, with_env("LIVE_BPM" => "180") { Livesets.grid(bed, 1.0) }[:bars_in_loop]
    end

    transport = { bar: 2.0, total: 16, marks: [[8.0, "phrase out"], [12.0, "phrase to 1.0"]] }
    assert_equal "bar 3/8  phrase out in 2 bar(s)   ", Livesets.transport_line(4.5, transport)
    assert_equal "bar 8/8   ", Livesets.transport_line(15.0, transport)
    assert_equal [[32.0, "phrase out"]], with_env("LIVE_FORM" => nil) {
      Livesets.arrangement("chord_based_beats", 2.0, 64, [[0, 1.0], [32.0, 0.0]]) && Livesets.instance_variable_get(:@transport)[:marks]
    }

    pid = Process.spawn("sleep", "5", pgroup: true)
    Livesets.instance_variable_set(:@stopping, false)
    capture_io { Livesets.interrupt!(pid) }
    assert Livesets.instance_variable_get(:@stopping)
    assert_nil Process.wait(pid, Process::WNOHANG), "the first Ctrl-C lets the pass play on"
    Livesets.interrupt!(pid)
    Process.wait(pid)
    assert_equal "TERM", Signal.signame($?.termsig)
  end

  # The kit: a groove from the engine's GROOVE_DNA that swings by percentage and
  # sets how hard each hit lands, the flat drunk swing for a take kept under it,
  # and a recorded kit that deals numbered takes in turn, plays its ghost off the
  # snare, trims each role to the reference and reads its crackle from noise.
  def test_the_kit_grooves_from_the_dna_and_a_recorded_kit_is_a_kit
    drunk = built("chord_based_beats", "LIVE_GROOVE" => "drunk", "LIVE_BPM" => "90")
    donuts = built("chord_based_beats", "LIVE_GROOVE" => nil, "LIVE_BPM" => "90")
    step_ms = (60.0 / 90 / 2 * 1000).round
    off = ->(pass) { (pass[:row][:drums][:hat_ms][1] - step_ms).round }

    assert_equal "donuts", donuts[:row][:groove]
    assert_in_delta 34, off.call(drunk), 7
    assert_in_delta Livesets.swing_ms(61, step_ms / 1000.0) + 14, off.call(donuts), 7
    refute(drunk[:graph].any? { |g| g.match?(/adelay=\d+\|\d+,volume=/) })
    assert(donuts[:graph].any? { |g| g.match?(/\[kkx0\]adelay=\d+\|\d+,volume=0\.84\[/) })
    assert_raises(SystemExit) { with_env("LIVE_GROOVE" => "polka") { Livesets.groove } }

    Dir.mktmpdir do |kit|
      %w[kick kick_2 snare hat].each do |name|
        system("ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "sine=f=200:d=0.2", "-af", "volume=-10dB", File.join(kit, "#{name}.wav"))
      end
      skip "ffmpeg is not installed" unless File.file?(File.join(kit, "hat.wav"))
      pass = built("sampled_based_beats", "LIVE_KIT" => kit)
      files = pass[:inputs].grep(/#{Regexp.escape(kit)}/)

      assert_equal %w[kick.wav kick_2.wav snare.wav hat.wav], files.map { |i| File.basename(i.split.last) }
      assert_empty Livesets.graph_problems(pass[:inputs], pass[:graph])
      assert_equal 1, pass[:graph].count { |g| g.start_with?("[kk0_s]asplit=1") }
      assert_equal 1, pass[:graph].count { |g| g.start_with?("[kk1_s]asplit=1") }
      snare = pass[:inputs].index { |i| i.end_with?("snare.wav") }
      assert(pass[:graph].any? { |g| g.start_with?("[#{snare}:a]volume=0.42") }, "the ghost is the snare")
      noise = pass[:inputs].index { |i| i.include?("a=0.006") }
      assert(pass[:graph].grep(/\[crackle\]\z/).first.start_with?("[#{noise}:a]"), "the crackle is the noise")
      # ffmpeg's sine peaks at an eighth of full scale, -18.1 dB, so -28.1 here.
      assert_in_delta(-4.7 - -28.1, Livesets.kit_trims(kit)[:kick], 0.5)
    end
  end

  # A named set is one of the three with its knobs set, journalled under its
  # name, and a knob exported by hand wins over the name.
  def test_every_named_set_builds_from_its_knobs_and_a_hand_set_knob_wins
    knobs = Livesets::NAMED_SETS.values.flat_map { |_, k| k.keys }.uniq.to_h { |k| [k, nil] }
    Livesets::NAMED_SETS.each do |name, (base, set_knobs)|
      pass = built(name, knobs)

      assert_empty Livesets.graph_problems(pass[:inputs], pass[:graph]), name
      assert_equal [name, base], [pass[:row][:named], pass[:row][:set]]
      assert_equal set_knobs["LIVE_LENGTH"].to_f, pass[:row][:seconds] if set_knobs["LIVE_LENGTH"]
    end
    gospel = built("gospel", knobs)[:row]
    assert_equal ["eight_bar_gospel_climb", 72.0, gospel[:bar_s]], [gospel[:progression_name], gospel[:bpm], gospel[:chord_s]]
    assert_equal 12.0, built("interlude", knobs.merge("LIVE_LENGTH" => "12"))[:row][:seconds]
    assert_nil built("chord_based_beats", knobs)[:row][:named]
    assert_includes built("minimal", knobs)[:row][:muted], "kit"
  end

  # Keeping: a kept take is a titled catalogue line saying whether it may be
  # released, a recall can change one choice, and a loudness target finishes
  # the chain.
  def test_a_kept_take_is_a_titled_catalogue_line_and_reopens_with_a_choice_changed
    Dir.mktmpdir do |dir|
      row = { "seed" => 7, "set" => "sampled_based_beats", "bed" => "be_ever_wonderful_03", "credit" => "Ted Taylor — unlicensed — u" }
      handed = nil
      clean = [[:lufs, -16.5, 0.0, { unit: "LUFS", range: (-18.0..-15.0) }], [:lra, 6.0, 0.0, { unit: "LU", range: (4.0..9.0) }]]
      stubs = { render_take!: ->(env, _) { handed = [env] }, score_take: -> { clean }, passes: -> { [row] },
                bed_rows: -> { { "be_ever_wonderful_03" => { "rights" => "unlicensed — rip" } } } }
      with_env("LIVE_CATALOGUE" => File.join(dir, "cat.json")) do
        stubbing(stubs) { capture_io { Livesets.recall!(%w[7 keep LIVE_ROOM=dry]) } }
        entry = Livesets.catalogue.last

        assert_equal "Ted Taylor (sampled 7)", entry["title"]
        refute entry["shareable"]
        assert_equal ["LIVE_ROOM=dry"], entry["overrides"]
        assert_equal "dry", handed.first.fetch("LIVE_ROOM")
        assert_equal Livesets::DEMO, handed.first.fetch("LIVE_RENDER_TO")
        assert_equal({ "value" => -16.5, "miss" => 0.0 }, entry.dig("mix", "lufs"))

        # A take that misses its window is not catalogued unless it is kept anyway.
        loud = [[:lufs, -10.5, 4.5, { unit: "LUFS", range: (-18.0..-15.0) }]]
        stubbing(stubs.merge(score_take: -> { loud })) do
          assert_raises(SystemExit) { capture_io { with_env("LIVE_KEEP_ANY" => nil) { Livesets.recall!(%w[7 keep]) } } }
          capture_io { with_env("LIVE_KEEP_ANY" => "1") { Livesets.recall!(%w[7 keep]) } }
        end
        assert_equal 2, Livesets.catalogue.size
      end
    end
    assert Livesets.shareable?("seed" => 1, "set" => "chord_based_beats")
    assert_equal "Lydian Augmented Haze (chord 1133818290)", Livesets.title_for(Livesets.passes.find { |r| r["seed"] == 1_133_818_290 })
    assert_includes built("ambient_pads", "LIVE_LUFS" => "-16")[:graph].grep(/\[out\]\z/).first, "loudnorm=I=-16.0:TP=-1.0"
    refute_includes built("ambient_pads", "LIVE_LUFS" => nil)[:graph].join, "loudnorm"
  end

  # Replay verification: the same seed rendered twice is the same audio. Three
  # determinism defects were found by doing this by hand; this does it every run,
  # on a four-second chord pass down a pipe.
  def test_a_seed_rendered_twice_is_the_same_audio
    skip "ffmpeg is not installed" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      env = { "LIVE_SEED" => "1133818290", "LIVE_LENGTH" => "4", "LIVE_RENDER_TO" => "-", "LIVE_JOURNAL" => File.join(dir, "j.jsonl"),
              "LIVE_KIT" => "synth", "DILLA_QUIET" => "1", "DILLA_ASSET_CHECK" => "0", "DILLA_KNOB_CHECK" => "0" }
      takes = Array.new(2) do
        wav, = Open3.capture2(env, RbConfig.ruby, File.join(__dir__, "..", "dilla", "dilla.rb"), "live", "set", "chord_based_beats", err: File::NULL, binmode: true)
        pcm, = Open3.capture2("ffmpeg", "-loglevel", "error", "-i", "-", "-f", "s16le", "-", stdin_data: wav, binmode: true)
        pcm.unpack("s<*")
      end

      assert_operator takes.first.size, :>, 44_100 * 2 * 3
      assert_equal takes.first.size, takes.last.size
      assert_equal 0, takes.first.zip(takes.last).map { |a, b| (a - b).abs }.max
    end
  end

  # A render writes demo.wav and no other audio file, and only takes its name
  # once it has finished, so a killed pass leaves the last good demo in place.
  def test_a_render_lands_on_demo_wav_only_and_arrives_whole
    Dir.mktmpdir do |dir|
      demo = File.join(dir, "demo.wav")
      File.write(demo, "last good")
      failing = "#{RbConfig.ruby.shellescape} -e 'File.write(ARGV.last, %(half)); exit 1' --"
      assert_raises(SystemExit) { Livesets.render_to!(failing, demo) }
      assert_equal "last good", File.read(demo)
      assert_equal %w[demo.wav], Dir.children(dir)

      writer = "#{RbConfig.ruby.shellescape} -e 'File.write(ARGV.last, %(audio))' --"
      Livesets.render_to!(writer, demo)
      assert_equal "audio", File.read(demo)
      assert_raises(SystemExit) { Livesets.render_to!(writer, File.join(dir, "chord_based_beats_7.wav")) }
      assert_equal %w[demo.wav], Dir.children(dir)
    end
  end

  # The live catalogue synthesises every sample in Ruby against a deadline, so
  # it turns the JIT on for itself. Answers for the interpreter it is running
  # under rather than assuming one: 3.4.9 here is built without YJIT.
  def test_player_command_targets_the_local_soundcard
    command = nil
    stubbing(audio_tool: ->(name) { name == "sox" ? "/tmp/sox" : nil }) do
      command = Livesets.player_command(32_000)
    end
    assert_equal "/tmp/sox", command.first
    assert_includes command, "-t"
    assert_includes command, "raw"
    assert_includes command, "-d"
    assert_includes command, "2"
  end

  def test_the_live_catalogue_asks_for_the_jit_and_says_what_it_got
    answer = DillaLive.accelerate!

    assert_includes %i[enabled already unavailable], answer
    if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)
      assert_predicate RubyVM::YJIT, :enabled?, "the live path asked for the JIT and did not get it"
      assert_equal :already, DillaLive.accelerate!, "asking twice must not restart the JIT"
    else
      assert_equal :unavailable, answer
    end
  end

  def test_a_recalled_pass_replays_the_voicing_it_was_journalled_under
    handed = nil
    row = { "seed" => 7, "set" => "sampled_based_beats", "bed" => "b", "voicing" => "up" }
    stubbing(exec: ->(*args) { handed = args }, passes: -> { [row] }) { Livesets.recall!(["7"]) }

    assert_equal "up", handed.first.fetch("LIVE_VOICING")
  end
end
