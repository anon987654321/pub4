# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../OPENBSD/lib/gate_result"

class GateResultSeverityTest < Minitest::Test
  def test_hard_fail_blocks
    r = Deploy::GateResult.new
    r.fail("boom", severity: :hard)
    refute r.ok?
    assert_equal ["boom"], r.failures
  end

  def test_soft_fail_is_warning_by_default
    r = Deploy::GateResult.new
    r.fail("taste", severity: :soft)
    assert r.ok?
    assert_includes r.soft_failures, "taste"
    assert r.warnings.any? { |w| w.include?("[soft]") && w.include?("taste") }
  end

  def test_strict_soft_promotes
    old = ENV["GATE_STRICT_SOFT"]
    ENV["GATE_STRICT_SOFT"] = "1"
    r = Deploy::GateResult.new
    r.fail("taste", severity: :soft)
    refute r.ok?
    assert r.failures.any? { |f| f.include?("taste") }
  ensure
    ENV["GATE_STRICT_SOFT"] = old
  end

  def test_merge_preserves_soft
    a = Deploy::GateResult.new
    b = Deploy::GateResult.new
    b.fail("soft-one", severity: :soft)
    b.fail("hard-one", severity: :hard)
    a.merge!(b)
    assert_includes a.soft_failures, "soft-one"
    assert_includes a.failures, "hard-one"
  end
end
