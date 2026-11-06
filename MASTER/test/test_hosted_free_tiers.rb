# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"

# Hosted free-tier day caps and per-provider key rotation landed on 2026-11-05 from a patch run against no
# Ruby. These hold its claims: a capped endpoint's lanes are counted against its own cap, an uncapped one
# stays untracked, and a hosted rotation reaches the next call's key.
class TestHostedFreeTiers < Minitest::Test
  Quota = Master::Io::ModelQuota
  Rotator = Master::Io::KeyRotator

  CONFIG = {
    "openrouter" => { "daily_quota_per_model" => 50 },
    "openai_compatible" => {
      "cerebras" => { "base" => "https://api.cerebras.ai/v1", "key_env" => %w[TEST_CEREBRAS_A TEST_CEREBRAS_B],
                      "daily_quota" => 100 },
      "nvidia" => { "base" => "https://integrate.api.nvidia.com/v1", "key_env" => %w[TEST_NVIDIA_A] },
    },
  }.freeze

  def long(seed) = seed * Master::MIN_API_KEY_LENGTH_HEURISTIC

  def test_a_capped_endpoint_counts_its_lanes_against_its_own_cap
    Master.stub(:models_config, CONFIG) do
      assert Quota.trackable?("cerebras:llama-3.3-70b")
      assert_equal 100, Quota.daily_limit_for("cerebras:llama-3.3-70b")
      Quota.stub(:count, 100) { assert Quota.over_quota?("cerebras:llama-3.3-70b") }
      Quota.stub(:count, 99) { refute Quota.over_quota?("cerebras:llama-3.3-70b") }
    end
  end

  def test_an_endpoint_without_a_cap_and_a_free_slug_keep_their_rules
    Master.stub(:models_config, CONFIG) do
      refute Quota.trackable?("nvidia:z-ai/glm-5.3-flash"), "no documented cap, no guessed one"
      assert_equal 50, Quota.daily_limit_for("nvidia/nemotron-3-super-120b-a12b:free")
    end
  end

  def with_two_keys
    saved = %w[TEST_CEREBRAS_A TEST_CEREBRAS_B].to_h { |var| [var, ENV.fetch(var, nil)] }
    positions = Rotator.instance_variable_get(:@positions).dup
    ENV["TEST_CEREBRAS_A"] = long("a")
    ENV["TEST_CEREBRAS_B"] = long("b")
    Master.stub(:models_config, CONFIG) { yield }
  ensure
    Rotator.instance_variable_set(:@positions, positions)
    saved.each { |var, value| value.nil? ? ENV.delete(var) : ENV[var] = value }
  end

  def test_a_hosted_rotation_reaches_the_next_calls_key
    with_two_keys do
      first = Rotator.active_key_for("cerebras")

      assert Rotator.rotate_for("cerebras:llama-3.3-70b")
      refute_equal first, Rotator.active_key_for("cerebras")
      refute Rotator.rotate_for("nvidia:z-ai/glm-5.3-flash"), "one key is a no-op"
    end
  end
end
