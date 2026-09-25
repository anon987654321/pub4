# frozen_string_literal: true

require_relative "dilla_helper"
require "json"
require "open3"

# The sine stream's two kept takes, resolved without rendering. lib/sine_stream.rb
# changes the working directory, sets drum-bus defaults in ENV and defines
# top-level constants when it loads, so it loads in a child process rather than
# in the suite's.
class TestDillaSineStream < Minitest::Test
  SINE_STREAM = File.expand_path("../dilla/lib/sine_stream.rb", __dir__)

  def in_sine_stream(script, env: {})
    probe = "require #{SINE_STREAM.dump}\nrequire \"json\"\n#{script}"
    out, err, status = Open3.capture3(DILLA_BOOT_ENV.merge(env), RbConfig.ruby, "-e", probe)
    assert status.success?, "sine stream probe failed: #{err}"
    JSON.parse(out.lines.last)
  end

  # Each row's feel, drum chain and depth are what the drivers derived from its
  # slot. If the rotation, the chain draw or the river's shape moves, the recipe
  # stops being the kept take, and this is where that shows.
  def test_every_demo_row_resolves_and_its_slot_still_derives_what_was_recorded
    result = in_sine_stream(<<~RUBY)
      cfg = dilla_resolve_config
      wrong = SINE_DEMO_ROWS.each_with_index.flat_map do |(name, stack, feel, chain, vocal, depth), slot|
        flow = flow_shape(slot)
        bars = sine_row_chords(name, cfg, flow[:chords]).length
        checks = {
          progression: CHORD_PROGRESSIONS.key?(name.to_sym) && bars.positive?,
          stack: PAD_LAYER_STACKS.key?(stack.to_sym),
          feel: feel_for((slot * 4 + bars - 1) / 4).to_s == feel,
          chain: drum_chain!([], [], slot * 977 + SINE_DEMO_CHAIN_SALT).join("-") == chain,
          vocal: VOCAL_DIRS.key?(vocal.to_sym),
          depth: "~\#{(flow[:depth] * 100).round}" == depth,
        }
        checks.reject { |_, ok| ok }.keys.map { |k| "\#{slot} \#{name} \#{k}" }
      end
      puts JSON.generate(rows: SINE_DEMO_ROWS.length, wrong: wrong)
    RUBY

    assert_equal 30, result.fetch("rows")
    assert_empty result.fetch("wrong")
  end

  def test_every_beat_row_resolves_to_four_chords_on_its_feel
    result = in_sine_stream(<<~RUBY)
      cfg = dilla_resolve_config
      wrong = SINE_BEAT_ROWS.each_with_index.flat_map do |(name, stack, feel, vocal), slot|
        checks = {
          progression: sine_row_chords(name, cfg, 4).length == 4,
          stack: PAD_LAYER_STACKS.key?(stack.to_sym),
          feel: feel_for(slot).to_s == feel,
          vocal: VOCAL_DIRS.key?(vocal.to_sym),
        }
        checks.reject { |_, ok| ok }.keys.map { |k| "\#{slot} \#{name} \#{k}" }
      end
      puts JSON.generate(rows: SINE_BEAT_ROWS.length, wrong: wrong)
    RUBY

    assert_equal 4, result.fetch("rows")
    assert_empty result.fetch("wrong")
  end

  def test_a_take_already_beside_dilla_rb_is_refused_before_any_work
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "sines_beat.wav"), "a take")
      result = in_sine_stream(<<~RUBY, env: { "DILLA_OUTPUT_DIR" => dir })
        refused = begin
          sine_take_path("sines_beat.wav")
          false
        rescue SystemExit
          true
        end
        puts JSON.generate(refused: refused, fresh: sine_take_path("sines_demo.mp3"))
      RUBY

      assert result.fetch("refused")
      assert_equal File.join(dir, "sines_demo.mp3"), result.fetch("fresh")
      assert_equal "a take", File.read(File.join(dir, "sines_beat.wav"))
    end
  end
end
