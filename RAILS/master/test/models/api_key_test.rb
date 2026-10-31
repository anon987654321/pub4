# frozen_string_literal: true

require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  def subscription(status: "active", plan: "master_api_team")
    { "id" => "sub_api_1", "status" => status, "customer" => "cus_1", "metadata" => { "plan" => plan },
      "items" => { "data" => [{ "current_period_end" => 1.month.from_now.to_i }] } }
  end

  test "a subscription to a law API plan makes one key row, and a replay updates it" do
    2.times { ApiKey.sync!(subscription, email: "dev@example.com") }

    key = ApiKey.find_by!(stripe_subscription_id: "sub_api_1")
    assert_equal 1, ApiKey.count
    assert key.entitling?
    assert_equal 10_000, key.quota
  end

  test "another app's plan makes no key" do
    assert_nil ApiKey.sync!(subscription(plan: "amber_premium_monthly"))
    assert_equal 0, ApiKey.count
  end

  test "the key is revealed once, authenticates by digest, and rotation retires it" do
    key = ApiKey.sync!(subscription)
    token = key.reveal!

    assert token.start_with?(ApiKey::PREFIX)
    assert_nil key.reveal!
    assert_equal key, ApiKey.authenticate(token)
    refute_includes ApiKey.pluck(:token_digest, :token_hint).flatten, token

    replacement = key.rotate!
    assert_nil ApiKey.authenticate(token)
    assert_equal key, ApiKey.authenticate(replacement)
  end

  test "checks count against the month's quota and a request that does not fit counts nothing" do
    key = ApiKey.sync!(subscription)
    key.update!(usage_period: ApiKey.current_period, usage_count: 9_995)

    assert_nil key.charge!(6)
    assert_equal 9_995, key.reload.usage_count
    assert_equal 10_000, key.charge!(5).used
  end

  test "a new month starts the count again" do
    key = ApiKey.sync!(subscription)
    key.update!(usage_period: "2000-01", usage_count: 10_000)

    assert_equal 3, key.charge!(3).used
  end
end
