# frozen_string_literal: true

require_relative "test_helper"

class TestSwallow < Minitest::Test
  def unique_context(label) = "test_swallow.#{label}.#{SecureRandom.hex(4)}"

  def test_log_defaults_to_cosmetic_severity_for_existing_call_sites
    ctx = unique_context("default")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx)

    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "cosmetic", entry["severity"]
  end

  def test_log_accepts_explicit_load_bearing_severity
    ctx = unique_context("tagged")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx, severity: :load_bearing)

    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "load_bearing", entry["severity"]
  end

  def test_log_falls_back_to_cosmetic_for_unrecognized_severity
    ctx = unique_context("bogus")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx, severity: :not_a_real_severity)

    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "cosmetic", entry["severity"]
  end

  def test_recent_filters_by_severity
    ctx = unique_context("filter")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx, severity: :load_bearing)
    Master::Ground::Swallow.log(RuntimeError.new("y"), context: ctx, severity: :cosmetic)

    load_bearing_only = Master::Ground::Swallow.recent(limit: 20, context: ctx, severity: :load_bearing)
    assert_equal 1, load_bearing_only.size
    assert_equal "x", load_bearing_only.first["error_message"]
  end

  def test_safe_call_forwards_severity
    ctx = unique_context("safe_call")
    result = Master::Ground::Swallow.safe_call(context: ctx, severity: :load_bearing) { raise "boom" }

    assert_nil result
    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "load_bearing", entry["severity"]
  end
end
