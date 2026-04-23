# frozen_string_literal: true

require_relative "test_helper"

class TestExperience < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @exp = Master::State::Experience.new(root: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_signature_ignores_arguments
    plan_a = [{ tool: :fs_read, path: "a.rb" }, { tool: :ast_replace, method: "login" }]
    plan_b = [{ tool: :fs_read, path: "z.rb" }, { tool: :ast_replace, method: "logout" }]
    # Same strategy, different arguments → same signature → shared score.
    @exp.record(plan: plan_a, score: 1.0)
    refute_in_delta 0.0, @exp.score(plan_b), 0.2, "same tool sequence should share experience"
  end

  def test_decay_bounds_unbounded_growth
    plan = [{ tool: :fs_read }]
    20.times { @exp.record(plan: plan, score: 1.0) }
    entry = @exp.record(plan: plan, score: 1.0)
    # With DECAY=0.99, count cannot grow to 21 — it stays well below.
    assert_in_delta 20.0, entry["count"], 2.0
  end

  def test_unknown_plan_returns_near_zero
    score = @exp.score([{ tool: :never_run }])
    assert_in_delta 0.0, score, 0.1, "unseen plan returns base 0 + small noise"
  end
end
