# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestEcosystemFeatures < Minitest::Test
  def test_model_quota_tracks_free_models
    dir = Dir.mktmpdir("master-quota-")
    path = File.join(dir, "model_quota.json")
    Master::Io::ModelQuota.stub(:path, path) do
      Master::Io::ModelQuota.stub(:daily_limit, 3) do
        model = "qwen/qwen3-coder:free"
        2.times { Master::Io::ModelQuota.record(model) }
        refute Master::Io::ModelQuota.over_quota?(model)
        Master::Io::ModelQuota.record(model)
        assert Master::Io::ModelQuota.over_quota?(model)
        refute Master::Io::ModelQuota.trackable?("deepseek-chat")
      end
    end
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_model_quota_rejects_corrupt_state
    dir = Dir.mktmpdir("master-quota-")
    path = File.join(dir, "model_quota.json")
    File.write(path, "{not-json")
    Master::Io::ModelQuota.stub(:path, path) do
      assert_raises(RuntimeError) { Master::Io::ModelQuota.count("qwen/qwen3-coder:free") }
      assert_raises(RuntimeError) { Master::Io::ModelQuota.exhausted_models }
    end
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_model_quota_does_not_swallow_accounting_write_failure
    Master::Io::ModelQuota.stub(:save_data, ->(_) { raise "disk full" }) do
      assert_raises(RuntimeError) { Master::Io::ModelQuota.record("qwen/qwen3-coder:free") }
    end
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
    # /orders and /soul joined on the same grounds: both handlers, both
    # subjects and both help entries existed, and control_commands was merged
    # into the table by nothing.
    # /plugin and /snapshot landed with a handler and a help entry. The rest of
    # that batch folded into verbs that already owned their subject, so the
    # command surface stays a number a person can hold: /status mission and
    # /status runtime, /doctor device, /model auth, /soul law, and /session for
    # sessions, continue, resume and fork. /rollback went with them: three
    # verbs meant three different rollbacks, and /undo is the one it aliased.
    assert_equal %w[clear commit doctor fix help model orders pair plugin
                    review rules session snapshot soul status undo why],
                 registry.keys.sort
  end

  def test_folded_verbs_answer_under_their_host
    registry = Master::CLI::CommandRegistry
    session = Master::Trace::Session.new

    assert_equal "sessions0: none", registry.dispatch_session(session, ctx: { args: "" })
    assert_match(/session0: forked /, registry.dispatch_session(session, ctx: { args: "fork" }))
    assert_match(/^\* /, registry.dispatch_session(session, ctx: { args: "list" }))
    assert_match(/session0: continued /, registry.dispatch_session(session, ctx: { args: "resume" }))
    assert_includes registry.dispatch_soul(nil, ctx: { args: "law bogus" }), "soul law contract"
    assert_includes registry.dispatch_doctor(Master::ROOT, ctx: { args: "device bogus" }), "doctor device"
    assert_includes registry.dispatch_model(agent: nil, config: nil, metrics: nil, root: Master::ROOT, arg: "auth bogus words"),
                    "model auth login"
    status = ->(args) { registry.dispatch_status(root: Master::ROOT, fix_loop: nil, bus: nil, git: nil, ctx: { args: }) }
    assert_includes status.("runtime bogus"), "status runtime promote"
    assert_match(/\Amission(0: none|: )/, status.("mission"))
  end
end
