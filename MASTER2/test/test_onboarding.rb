# frozen_string_literal: true

require_relative "test_helper"

class TestOnboarding < Minitest::Test
  def test_responds_to_public_api
    assert_respond_to MASTER::Onboarding, :start
    assert_respond_to MASTER::Onboarding, :complete?
  end

  def test_onboarding_module_exists
    assert defined?(MASTER::Onboarding), "MASTER::Onboarding should be defined"
  end
end
