# frozen_string_literal: true

require "test_helper"

class DinteroHooksTest < ActiveSupport::TestCase
  setup do
    @saved = {
      "DINTERO_ACCOUNT_ID" => ENV["DINTERO_ACCOUNT_ID"],
      "DINTERO_CLIENT_ID" => ENV["DINTERO_CLIENT_ID"],
      "DINTERO_CLIENT_SECRET" => ENV["DINTERO_CLIENT_SECRET"],
      "DINTERO_HOOK_SECRET" => ENV["DINTERO_HOOK_SECRET"],
      "DINTERO_HOOK_URL" => ENV["DINTERO_HOOK_URL"]
    }
    ENV["DINTERO_ACCOUNT_ID"] = "P12345678"
    ENV["DINTERO_CLIENT_ID"] = "client"
    ENV["DINTERO_CLIENT_SECRET"] = "secret"
    ENV["DINTERO_HOOK_SECRET"] = "hook"
    ENV["DINTERO_HOOK_URL"] = "https://markedsplass.brgen.no/webhooks/dintero"
  end

  teardown do
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "subscription body carries the marketplace event set" do
    body = Marketplace::Payments::DinteroHooks.subscription_body
    assert_equal "https://markedsplass.brgen.no/webhooks/dintero", body[:config][:url]
    assert_equal "hook", body[:config][:secret]
    assert_includes body[:events], "checkout_authorization"
    assert_includes body[:events], "checkout_transaction"
    assert_includes body[:events], "approval_payout_destination_update"
    assert_includes body[:events], "settlement_add"
  end

  test "non-https webhook urls are refused before API traffic" do
    ENV["DINTERO_HOOK_URL"] = "http://markedsplass.brgen.no/webhooks/dintero"
    assert_raises(ArgumentError) { Marketplace::Payments::DinteroHooks.subscription_body }
  end
end
