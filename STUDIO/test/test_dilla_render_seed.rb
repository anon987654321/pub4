# frozen_string_literal: true

require_relative "dilla_helper"

# RENDER_SEED is the engine's one reproducibility claim, and it has been wrong
# twice: once because ffmpeg's anoisesrc drew a fresh seed per process at 31
# call sites, and once because twenty-six sites built seeds out of String#hash,
# which Ruby randomises per process. Both times the pin read as real and was
# not, and the only way to tell was to render twice and diff samples.
#
# These pin the arithmetic instead. Every value below is reproduced from the
# implementation's own definition, not copied from a run.
class TestRenderSeed < Minitest::Test
  # djb2, written in the engine precisely so it does not change between
  # processes. If this fails, every "pinned" render before it drew different
  # drums and nothing said so.
  def test_stable_hash_is_stable_across_processes
    assert_equal 5381, send(:stable_hash, "")
    assert_equal 193_485_963, send(:stable_hash, "abc")
    assert_equal 256_638_987, send(:stable_hash, "dilla")
  end

  def test_stable_hash_coerces_and_stays_in_range
    %w[snare hat_up db_major_minor_fall].each do |tag|
      value = send(:stable_hash, tag)
      assert_operator value, :>=, 0
      assert_operator value, :<, NOISE_SEED_MODULUS
    end
    assert_equal send(:stable_hash, "7"), send(:stable_hash, 7),
                 "stable_hash goes through to_s, so a symbol and its string agree"
  end

  def test_render_pinned_follows_the_environment
    with_env("RENDER_SEED" => nil) { refute send(:render_pinned?) }
    with_env("RENDER_SEED" => "") { refute send(:render_pinned?), "empty is unset" }
    with_env("RENDER_SEED" => "7") { assert send(:render_pinned?) }
  end

  # -1 is ffmpeg's own "fresh seed per process" default. Returning it unpinned
  # is what keeps pinning opt-in.
  def test_noise_seed_is_ffmpegs_default_when_unpinned
    with_env("RENDER_SEED" => nil) do
      assert_equal(-1, send(:noise_seed, "snare"))
    end
  end

  def test_noise_seed_is_deterministic_and_in_uint32_when_pinned
    with_env("RENDER_SEED" => "42") do
      first = send(:noise_seed, "snare")
      assert_equal first, send(:noise_seed, "snare")
      assert_operator first, :>=, 0
      assert_operator first, :<, NOISE_SEED_MODULUS
    end
  end

  # The whole reason seed_for takes a tag: one seed shared by the snare's noise
  # and the hat's noise makes them the same signal, which reads as phasing
  # rather than as two drums.
  def test_seeds_decorrelate_across_tags
    with_env("RENDER_SEED" => "42") do
      tags = %w[snare hat_up shaker brush crackle rumble]
      seeds = tags.map { |tag| send(:noise_seed, tag) }
      assert_equal seeds.size, seeds.uniq.size, "two noise sources drew the same seed"
    end
  end

  def test_a_different_pin_gives_a_different_render
    a = with_env("RENDER_SEED" => "1") { send(:noise_seed, "snare") }
    b = with_env("RENDER_SEED" => "2") { send(:noise_seed, "snare") }
    refute_equal a, b
  end

  def test_render_rand_stays_in_the_unit_interval
    with_env("RENDER_SEED" => "42") do
      value = send(:render_rand, "swing")
      assert_operator value, :>=, 0.0
      assert_operator value, :<, 1.0
      assert_equal value, send(:render_rand, "swing")
    end
  end

  # Keyed by tag rather than by call order, because drum_sample_path is called
  # once per role and an order-keyed RNG hands a role a different file depending
  # on which roles resolved before it.
  def test_render_pick_is_keyed_by_tag_not_call_order
    list = %w[a b c d e]
    with_env("RENDER_SEED" => "42") do
      kick = send(:render_pick, list, "kick")
      snare = send(:render_pick, list, "snare")

      assert_includes list, kick
      assert_equal kick, send(:render_pick, list, "kick"),
                   "picking for another role in between moved this role's file"
      assert_equal snare, send(:render_pick, list, "snare")
    end
  end

  def test_render_pick_handles_an_empty_crate
    with_env("RENDER_SEED" => "42") do
      assert_nil send(:render_pick, [], "kick")
      assert_nil send(:render_pick, nil, "kick")
    end
  end

  def test_render_rng_is_a_real_random_and_repeats_under_a_pin
    with_env("RENDER_SEED" => "42") do
      first = send(:render_rng, "evolve").rand(1000)
      assert_equal first, send(:render_rng, "evolve").rand(1000)
    end
  end

  # drift exists so two evolution sites sharing a tag do not share a stream.
  def test_render_rng_drift_separates_unpinned_streams
    with_env("RENDER_SEED" => nil) do
      assert_instance_of Random, send(:render_rng, "evolve", drift: 5)
    end
  end

  # SEED_TEXT is the other half of the same promise, and it was broken the same
  # way: it derived from String#hash, which Ruby randomises per process, so the
  # one knob whose whole purpose is a repeatable seed named a different seed
  # every run — and SWING and BPM, derived from the same value, moved with it.
  # A digest is stable where a hash is not, and this is what says so.
  def test_seed_text_names_the_same_seed_in_every_process
    expected = Digest::SHA256.hexdigest("bergen regn").to_i(16) % (1 << 62)

    assert_equal expected, DillaSeeds.stable_seed("bergen regn")
    assert_equal DillaSeeds.stable_seed("bergen regn"), DillaSeeds.stable_seed("bergen regn")
    refute_equal DillaSeeds.stable_seed("bergen regn"), DillaSeeds.stable_seed("bergen sol")
  end

  # The derived knobs are the reason this matters past the seed: an operator who
  # pins the text has pinned the groove and the tempo too.
  def test_seed_text_pins_swing_and_bpm_with_it
    keys = %w[SEED_TEXT GEN_SEED SWING BPM]
    runs = 2.times.map do
      with_env(keys.zip([ "bergen regn", nil, nil, nil ]).to_h) do
        DillaSeeds.apply_text_seed!
        ENV.values_at("GEN_SEED", "SWING", "BPM")
      end
    end

    assert_equal runs.first, runs.last
    refute_includes runs.first, nil, "a pinned text must fill all three"
  end
end
