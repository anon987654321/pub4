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

  # The one take kept through `recall keep` before renders/ went. Its journal
  # row is what recall reads, so the seed has to reach the set it names with
  # the kit and the progression it played, not whatever is exported today.
  def test_the_kept_take_recalls_from_the_journal
    handed = nil
    Livesets.define_singleton_method(:exec) { |*args| handed = args }
    Livesets.recall!(["1133818290"])
    env, _ruby, _engine, *command = handed

    assert_equal %w[live set chord_based_beats], command
    assert_equal({ "LIVE_SEED" => "1133818290", "LIVE_KIT" => "synth",
                   "LIVE_PROGRESSION" => "lydian_augmented_haze" }, env)
  ensure
    Livesets.singleton_class.remove_method(:exec)
  end

  # A pin replaces what the seed drew and nothing after it: the draw still
  # happens, so the tempo and the drums a replay rolls next are the same rolls.
  def test_a_pinned_progression_leaves_the_stream_where_the_draw_left_it
    unpinned = with_env("LIVE_PROGRESSION" => nil) { srand(41) && [Livesets.pick_progression, rand] }
    pinned = with_env("LIVE_PROGRESSION" => "lydian_augmented_haze") { srand(41) && [Livesets.pick_progression, rand] }

    assert_equal :lydian_augmented_haze, pinned.first
    assert_equal unpinned.last, pinned.last
  end
end
