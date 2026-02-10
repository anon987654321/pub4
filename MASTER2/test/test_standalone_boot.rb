# frozen_string_literal: true

require "minitest/autorun"

class TestStandaloneBoot < Minitest::Test
  def test_master_module_defined
    require_relative "../lib/result"
    assert defined?(MASTER::Result), "MASTER::Result should be defined"
  end

  def test_result_ok
    require_relative "../lib/result"
    r = MASTER::Result.ok(42)
    assert r.ok?
    refute r.err?
    assert_equal 42, r.value
  end

  def test_result_err
    require_relative "../lib/result"
    r = MASTER::Result.err("boom")
    assert r.err?
    refute r.ok?
    assert_equal "boom", r.error
  end

  def test_result_ok_nil_is_ok
    require_relative "../lib/result"
    r = MASTER::Result.ok(nil)
    assert r.ok?, "Result.ok(nil) must be ok"
    assert_nil r.value
  end

  def test_result_map
    require_relative "../lib/result"
    r = MASTER::Result.ok(5).map { |v| v * 2 }
    assert r.ok?
    assert_equal 10, r.value
  end

  def test_result_and_then
    require_relative "../lib/result"
    r = MASTER::Result.ok(5).and_then("double") { |v| MASTER::Result.ok(v * 2) }
    assert r.ok?
    assert_equal 10, r.value
  end

  def test_result_frozen_string_value
    require_relative "../lib/result"
    r = MASTER::Result.ok("hello")
    assert r.value.frozen?, "String values should be frozen"
  end

  def test_result_frozen_array_value
    require_relative "../lib/result"
    r = MASTER::Result.ok([1, 2, 3])
    assert r.value.frozen?, "Array values should be frozen"
  end
end
