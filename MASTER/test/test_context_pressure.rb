# frozen_string_literal: true

require_relative "test_helper"

class TestContextPressure < Minitest::Test
  def test_snapshot_ok_band
    session = Struct.new(:token_est).new(10_000)
    snap = Master::Trace::ContextPressure.snapshot(session:, limit: 100_000)
    assert_equal "ok", snap[:band]
    assert_equal 10.0, snap[:pct]
    assert_equal 90_000, snap[:headroom]
  end

  def test_snapshot_critical_band
    session = Struct.new(:token_est).new(95_000)
    snap = Master::Trace::ContextPressure.snapshot(session:, limit: 100_000)
    assert_equal "critical", snap[:band]
  end
end
