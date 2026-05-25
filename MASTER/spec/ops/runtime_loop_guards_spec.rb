# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/master"
require_relative "../../lib/ops/runtime_loop_guards"

module Master
  module Loop
    class Heartbeat
      attr_reader :started

      def start!
        @started = true
      end
    end unless const_defined?(:Heartbeat)
  end
end

class RuntimeLoopGuardsSpec < Minitest::Test
  def with_heartbeat_env(value)
    old = ENV["MASTER_HEARTBEAT"]
    value.nil? ? ENV.delete("MASTER_HEARTBEAT") : ENV["MASTER_HEARTBEAT"] = value
    yield
  ensure
    old.nil? ? ENV.delete("MASTER_HEARTBEAT") : ENV["MASTER_HEARTBEAT"] = old
  end

  def test_heartbeat_start_is_blocked_without_explicit_env
    with_heartbeat_env(nil) do
      Master::Ops::RuntimeLoopGuards.install!
      heartbeat = Master::Loop::Heartbeat.new
      heartbeat.start!
      refute heartbeat.started
    end
  end

  def test_heartbeat_start_runs_with_explicit_env
    with_heartbeat_env("1") do
      Master::Ops::RuntimeLoopGuards.install!
      heartbeat = Master::Loop::Heartbeat.new
      heartbeat.start!
      assert heartbeat.started
    end
  end
end
