# frozen_string_literal: true

require "test_helper"

# The money path's worst failure was not "unconfigured" — it was
# MISconfigured: a production box missing one variable once took a customer
# through a perfect-looking checkout against Vipps' test environment (order
# marked paid, no money). api_base's decision table is that contract, and it
# had no test calling it.
class VippsCheckoutConfigTest < ActiveSupport::TestCase
  KEYS = %w[VIPPS_EPAYMENT_CLIENT_ID VIPPS_EPAYMENT_CLIENT_SECRET VIPPS_MSN
            VIPPS_SUBSCRIPTION_KEY VIPPS_API_BASE VIPPS_TEST_MODE].freeze

  setup { @saved = KEYS.to_h { |k| [k, ENV[k]] }; KEYS.each { |k| ENV.delete(k) } }
  teardown { @saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v } }

  def prod(&block)
    Rails.env.stub(:production?, true, &block)
  rescue NoMethodError
    original = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))
    block.call
  ensure
    Rails.instance_variable_set(:@_env, original) if original
  end

  test "unconfigured is unconfigured — no key fakes readiness" do
    assert_not Marketplace::Payments::VippsCheckout.configured?
    ENV["VIPPS_EPAYMENT_CLIENT_ID"] = "id"
    ENV["VIPPS_EPAYMENT_CLIENT_SECRET"] = "secret"
    ENV["VIPPS_MSN"] = "123456"
    assert_not Marketplace::Payments::VippsCheckout.configured?, "three of four keys is not configured"
    ENV["VIPPS_SUBSCRIPTION_KEY"] = "sub"
    assert Marketplace::Payments::VippsCheckout.configured?
  end

  test "production refuses an explicit test endpoint unless test mode says so out loud" do
    ENV["VIPPS_API_BASE"] = "https://apitest.vipps.no"
    prod do
      assert_raises(Marketplace::Payments::NotConfigured) do
        Marketplace::Payments::VippsCheckout.api_base
      end
      ENV["VIPPS_TEST_MODE"] = "1"
      assert_equal "https://apitest.vipps.no", Marketplace::Payments::VippsCheckout.api_base,
        "deliberate test mode is allowed — it just has to say so"
    end
  end

  test "production without an explicit base uses the live host, never the test default" do
    prod do
      assert_equal Marketplace::Payments::VippsCheckout::LIVE_API_BASE,
                   Marketplace::Payments::VippsCheckout.api_base
    end
  end

  test "outside production an explicit base is honored as written" do
    ENV["VIPPS_API_BASE"] = "https://apitest.vipps.no"
    assert_equal "https://apitest.vipps.no", Marketplace::Payments::VippsCheckout.api_base
  end
end
