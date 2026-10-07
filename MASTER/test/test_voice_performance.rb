# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/performance"

class TestVoicePerformance < Minitest::Test
  def test_plan_is_deterministic
    first = Master::Voice::Performance.plan("The key is simple. But timing matters.")
    second = Master::Voice::Performance.plan("The key is simple. But timing matters.")

    assert_equal first, second
  end

  def test_plan_creates_bounded_variation
    plan = Master::Voice::Performance.plan(
      "Start here. However, there is a risk. Are you sure? The key is simple.",
    )

    assert_operator plan.length, :>, 1
    plan.each do |part|
      assert_includes(-6..6, part[:rate_delta])
      assert_includes(-14..14, part[:pitch_delta_hz])
      assert_includes(90..480, part[:pause_ms])
    end
  end

  def test_apply_preserves_safe_engine_ranges
    plan = Master::Voice::Performance.apply(
      base_rate: "+18%",
      base_pitch: "+55Hz",
      text: "Hello. But be careful.",
    )

    plan.each do |part|
      assert_operator part[:rate].delete("%").to_i, :<=, 10
      assert_operator part[:rate].delete("%").to_i, :>=, -12
      assert_operator part[:pitch].delete("Hz").to_i, :<=, 24
      assert_operator part[:pitch].delete("Hz").to_i, :>=, -24
    end
  end

  def test_roles_are_semantic
    plan = Master::Voice::Performance.plan(
      "The answer starts here. However, the timing matters. Are you sure? The key is this.",
    )

    assert_equal :opening, plan[0][:role]
    assert_equal :contrast, plan[1][:role]
    assert_equal :question, plan[2][:role]
    assert_equal :closing, plan[3][:role]
  end

  def test_clause_markers_change_role_without_splitting
    plan = Master::Voice::Performance.plan("The key is this: it matters, actually. Then continue.")

    assert_equal 2, plan.length
    assert_equal :reveal, plan[0][:role]
  end

  def test_phrase_variation_changes_are_smoothed
    plan = Master::Voice::Performance.plan(
      "Start here. However, there is a risk. Are you sure? The key is simple.",
    )

    plan.each_cons(2) do |previous, current|
      assert_operator (current[:rate_delta] - previous[:rate_delta]).abs, :<=,
                      Master::Voice::Performance::MAX_RATE_STEP
      assert_operator (current[:pitch_delta_hz] - previous[:pitch_delta_hz]).abs, :<=,
                      Master::Voice::Performance::MAX_PITCH_STEP_HZ
    end
  end
end
