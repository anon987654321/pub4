# frozen_string_literal: true

require "minitest/autorun"

class TestSubscriptionAuth < Minitest::Test
  def test_profiles_are_subscription_only
    profiles = Master::Ground::SubscriptionAuth.profiles
    refute_empty profiles
    assert profiles.all? { |lane| lane["auth"] == "subscription" }
  end

  def test_unknown_provider_is_safe
    assert_match(/unknown subscription/, Master::Ground::SubscriptionAuth.login("does-not-exist"))
  end
end
