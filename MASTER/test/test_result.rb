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

  def test_err_includes_required_context_keys
    r = Master::Result.err("boom", category: :unknown)

    assert_includes r.context.keys, :file
    assert_includes r.context.keys, :method
    assert_equal "boom", r.context[:attempted]
  end

  def test_err_preserves_supplied_context
    r = Master::Result.err(
      "boom",
      category: :unknown,
      context: { file: "custom.rb", method: "call", attempted: "open socket", detail: "timeout" },
    )

    assert_equal "custom.rb", r.context[:file]
    assert_equal "call", r.context[:method]
    assert_equal "open socket", r.context[:attempted]
    assert_equal "timeout", r.context[:detail]
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

  def test_from_converts_nil_to_typed_error
    result = Master::Result.from(nil, err_msg: "missing", category: :validation)

    assert result.err?
    assert_equal :validation, result.category
  end

  def test_from_wraps_non_nil_value
    result = Master::Result.from(false, err_msg: "missing")

    assert result.ok?
    assert_equal false, result.value!
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
