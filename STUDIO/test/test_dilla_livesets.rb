# frozen_string_literal: true

require_relative "dilla_helper"
require_relative "../dilla/lib/livesets"

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
    assert_equal({ "LIVE_SEED" => "1133818290", "LIVE_KIT" => "synth",
                   "LIVE_PROGRESSION" => "lydian_augmented_haze" }, env)
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
    row = built("chord_based_beats", "LIVE_SEED" => kept["seed"].to_s, "LIVE_KIT" => kept["kit"],
                                     "LIVE_PROGRESSION" => kept["progression_name"])[:row]

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

  def test_a_recalled_pass_replays_the_voicing_it_was_journalled_under
    handed = nil
    row = { "seed" => 7, "set" => "sampled_based_beats", "bed" => "b", "voicing" => "up" }
    stubbing(exec: ->(*args) { handed = args }, passes: -> { [row] }) { Livesets.recall!(["7"]) }

    assert_equal "up", handed.first.fetch("LIVE_VOICING")
  end
end
