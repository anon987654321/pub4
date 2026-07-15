# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/master"
require_relative "../../lib/ops/runtime_loop_guards"

# RuntimeLoopGuards.install! monkey-patches the *real* Master::Loop::Heartbeat
# via class_eval (see lib/ops/runtime_loop_guards.rb) — it is not designed to
# work against a test double, so this spec exercises the real class directly.
# Guard against double-aliasing across repeated `install!` calls in one
# process: only patch once per test process, like production boot does.
class RuntimeLoopGuardsSpec < Minitest::Test
  def with_heartbeat_env(value)
    old = ENV["MASTER_HEARTBEAT"]
    value.nil? ? ENV.delete("MASTER_HEARTBEAT") : ENV["MASTER_HEARTBEAT"] = value
    yield
  ensure
    old.nil? ? ENV.delete("MASTER_HEARTBEAT") : ENV["MASTER_HEARTBEAT"] = old
  end

  def build_heartbeat
    Dir.mktmpdir { |dir| return Master::Loop::Heartbeat.new(root: dir) }
  end

  def test_heartbeat_start_is_blocked_without_explicit_env
    Master::Ops::RuntimeLoopGuards.install!

    with_heartbeat_env(nil) do
      heartbeat = build_heartbeat
      result = heartbeat.start!
      assert_nil result
    end
  end

  def test_heartbeat_start_runs_with_explicit_env
    Master::Ops::RuntimeLoopGuards.install!

    with_heartbeat_env("1") do
      heartbeat = build_heartbeat
      begin
        heartbeat.start!
        assert heartbeat.instance_variable_get(:@thread)
      ensure
        heartbeat.instance_variable_get(:@thread)&.kill
      end
    end
  end
end
