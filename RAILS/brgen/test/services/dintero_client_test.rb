# frozen_string_literal: true

require "test_helper"

class DinteroClientTest < ActiveSupport::TestCase
  setup do
    @saved = %w[DINTERO_API_BASE DINTERO_CHECKOUT_BASE DINTERO_TEST_MODE]
      .to_h { |key| [ key, ENV[key] ] }
    ENV.delete("DINTERO_API_BASE")
    ENV.delete("DINTERO_CHECKOUT_BASE")
    ENV.delete("DINTERO_TEST_MODE")
  end

  teardown do
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "non-production defaults to Dintero test hosts" do
    assert_equal Marketplace::Payments::DinteroClient::TEST_API_HOST,
                 Marketplace::Payments::DinteroClient.api_host
    assert_equal Marketplace::Payments::DinteroClient::TEST_CHECKOUT_HOST,
                 Marketplace::Payments::DinteroClient.checkout_host
  end

  test "production defaults to live hosts" do
    original = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))
    assert_equal Marketplace::Payments::DinteroClient::LIVE_API_HOST,
                 Marketplace::Payments::DinteroClient.api_host
    assert_equal Marketplace::Payments::DinteroClient::LIVE_CHECKOUT_HOST,
                 Marketplace::Payments::DinteroClient.checkout_host
  ensure
    Rails.instance_variable_set(:@_env, original)
  end

  test "production rejects an explicit test host unless test mode is enabled" do
    ENV["DINTERO_API_BASE"] = Marketplace::Payments::DinteroClient::TEST_API_HOST
    original = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))
    assert_raises(ArgumentError) { Marketplace::Payments::DinteroClient.api_host }
    ENV["DINTERO_TEST_MODE"] = "1"
    assert_equal Marketplace::Payments::DinteroClient::TEST_API_HOST,
                 Marketplace::Payments::DinteroClient.api_host
  ensure
    Rails.instance_variable_set(:@_env, original)
  end

  test "arbitrary API hosts are refused" do
    ENV["DINTERO_API_BASE"] = "https://example.invalid"
    assert_raises(ArgumentError) { Marketplace::Payments::DinteroClient.api_host }
  end
end
