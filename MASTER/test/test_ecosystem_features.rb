# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestEcosystemFeatures < Minitest::Test
  def test_model_quota_tracks_free_models
    dir = Dir.mktmpdir("master-quota-")
    path = File.join(dir, "model_quota.json")
    Master::Ground::ModelQuota.stub(:path, path) do
      Master::Ground::ModelQuota.stub(:daily_limit, 3) do
        model = "qwen/qwen3-coder:free"
        2.times { Master::Ground::ModelQuota.record(model) }
        refute Master::Ground::ModelQuota.over_quota?(model)
        Master::Ground::ModelQuota.record(model)
        assert Master::Ground::ModelQuota.over_quota?(model)
        refute Master::Ground::ModelQuota.trackable?("deepseek-chat")
      end
    end
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_cache_efficiency_snapshot
    Master::Trace::CacheEfficiency.reset!
    Master::Trace::CacheEfficiency.record(input: 1000, cached: 870)
    snap = Master::Trace::CacheEfficiency.snapshot
    assert_in_delta 87.0, snap[:efficiency_pct], 0.1
    assert_equal 870, snap[:cached_tokens]
  end

  def test_context_pressure_compacting_band
    session = Object.new
    session.define_singleton_method(:token_est) { 130_000 }
    snap = Master::Trace::ContextPressure.snapshot(session:, limit: 200_000)
    assert_equal "compacting", snap[:band]
  end

  def test_doctor_command_registered
    infra = { session: Master::Trace::Session.new, config: {}, root: Master::ROOT, bus: nil }
    ai = { agent: nil }
    registry = Master::CLI::CommandRegistry.build(infra:, ai:, root: Master::ROOT)
    # /why joins the surface: its handler, its Trace::WhyExplainer and its place
    # in the next-action chips all existed; only the registration was missing.
    assert_equal %w[clear commit doctor help model pair rollback status through undo why], registry.keys.sort
  end
end
