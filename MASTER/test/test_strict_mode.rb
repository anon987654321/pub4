# frozen_string_literal: true

require_relative "test_helper"
require "operator/strict_mode"

class TestStrictMode < Minitest::Test
  def test_contribute_is_non_strict
    env = { "MASTER_STRICT" => "contribute" }
    refute Operator::StrictMode.enabled?(env)
    assert_equal "0", Operator::StrictMode.flags(env)["GATE_REQUIRE_LIVE"]
  end

  def test_deploy_enables_all_four_strict_gate_dimensions
    env = { "MASTER_STRICT" => "deploy" }
    assert Operator::StrictMode.enabled?(env)
    assert_equal %w[1 1 1 1],
      %w[GATE_STRICT_INCONCLUSIVE GATE_STRICT_ERRORS GATE_STRICT_SOFT GATE_REQUIRE_LIVE].map { |key| Operator::StrictMode.flags(env)[key] }
  end

  def test_release_is_an_alias_for_deploy
    assert_equal :deploy, Operator::StrictMode.mode("MASTER_STRICT" => "release")
  end
end
