# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pub4/check_brief"
require_relative "../lib/pub4/check_runner"

class TestCheckBrief < Minitest::Test
  def test_selftest_hint_is_known_debt
    hint = Pub4::CheckBrief.hint_for("selftest")
    assert_equal "known_debt", hint[:category]
    assert_equal "agent-ignore", hint[:debt_tag]
  end

  def test_render_clean
    results = [
      Pub4::CheckRunner::Result.new(name: "lint:data_singularity", success: true, output: ""),
    ]
    output = Pub4::CheckBrief.render(profile: "agent", results:)
    assert_includes output, "status: clean"
    assert_includes output, "checks_passed: 1/1"
  end

  def test_render_failure
    results = [
      Pub4::CheckRunner::Result.new(name: "selftest", success: false, output: "ROBUSTNESS: lib/foo.rb\n"),
      Pub4::CheckRunner::Result.new(name: "lint:data_singularity", success: true, output: ""),
    ]
    output = Pub4::CheckBrief.render(profile: "agent", results:)
    assert_includes output, "status: fail"
    assert_includes output, "first_failure: selftest"
    assert_includes output, "category: known_debt"
    assert_includes output, "debt_tag: agent-ignore"
    assert_includes output, "checks_remaining: 1/2"
  end
end