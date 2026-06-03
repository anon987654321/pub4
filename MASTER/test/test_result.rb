# frozen_string_literal: true

require_relative "test_helper"

class TestResult < Minitest::Test
  def test_ok_holds_value
    r = Master::Result.ok("hello")
    assert r.ok?
    refute r.err?
    assert_equal "hello", r.value!
  end

  def test_err_holds_message
    r = Master::Result.err("boom", category: :unknown)
    assert r.err?
    refute r.ok?
    assert_equal "boom", r.message
  end

  def test_and_then_chains_on_ok
    r = Master::Result.ok(2).and_then { |v| Master::Result.ok(v * 3) }
    assert r.ok?
    assert_equal 6, r.value!
  end

  def test_and_then_short_circuits_on_err
    r = Master::Result.err("fail").and_then { |_| Master::Result.ok("never") }
    assert r.err?
    assert_equal "fail", r.message
  end

  def test_and_then_wraps_plain_value
    r = Master::Result.ok(5).and_then { |v| v * 2 }
    assert r.ok?
    assert_equal 10, r.value!
  end
end

class TestResultContext < Minitest::Test
  def test_err_always_carries_evidence_context
    result = Master::Result.err("boom", category: :validation)

    assert_kind_of Hash, result.context
    assert result.context[:file].end_with?("test_result.rb")
    assert_equal "test_err_always_carries_evidence_context", result.context[:method]
    assert_equal "boom", result.context[:attempted]
  end
end
