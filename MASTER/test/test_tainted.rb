# frozen_string_literal: true

require_relative "test_helper"

# CaMeL taint-tracking: untrusted values are wrapped and refused by privileged tool calls.
class TestTainted < Minitest::Test
  Taint = Master::Ground::Taint

  def test_wraps_and_unwraps
    tagged = Taint.wrap("rm -rf /", source: "web_fetch")
    assert Taint.tainted?(tagged)
    assert_equal "rm -rf /", Taint.clean(tagged)
    assert_equal "web_fetch", tagged.source
  end

  def test_wrap_is_idempotent
    once = Taint.wrap("x", source: "read_file")
    twice = Taint.wrap(once, source: "read_file")
    assert_same once, twice
  end

  def test_taint_propagates_through_collections
    args = { cmd: Taint.wrap("danger", source: "web"), flag: "safe" }
    assert Taint.tainted?(args)
    refute Taint.safe_for_privileged?(args)
  end

  def test_clean_values_are_safe
    assert Taint.safe_for_privileged?({ path: "lib/x.rb", n: 1 })
    refute Taint.tainted?("plain string")
  end
end
