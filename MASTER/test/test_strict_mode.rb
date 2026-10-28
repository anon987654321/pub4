# frozen_string_literal: true

require_relative "test_helper"
require "operator/strict_mode"

class TestStrictMode < Minitest::Test
  def test_contribute_is_non_strict
    env = { "MASTER_STRICT" => "contribute" }
    refute Operator::StrictMode.enabled?(env)
    assert_equal "0", Operator::StrictMode.flags(env)["CHECK_REQUIRE_LIVE"]
  end

  def test_deploy_enables_all_three_configurable_strict_check_dimensions
    env = { "MASTER_STRICT" => "deploy" }
    assert Operator::StrictMode.enabled?(env)
    assert_equal %w[1 1 1],
      %w[CHECK_STRICT_INCONCLUSIVE CHECK_STRICT_SOFT CHECK_REQUIRE_LIVE].map { |key| Operator::StrictMode.flags(env)[key] }
    refute Operator::StrictMode.flags(env).key?("CHECK_STRICT_ERRORS")
  end

  def test_release_is_an_alias_for_deploy
    assert_equal :deploy, Operator::StrictMode.mode("MASTER_STRICT" => "release")
  end
end
