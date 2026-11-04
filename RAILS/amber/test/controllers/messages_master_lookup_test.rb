# frozen_string_literal: true

require "test_helper"

# MessagesController looked the MASTER bot up by email in master_invited?,
# resolve_recipient and load_inbox, so the inbox ran the same find_by three
# times per request.
class MessagesMasterLookupTest < ActionDispatch::IntegrationTest
  test "the inbox looks the MASTER bot up once" do
    email = "ml-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    User.master_bot

    lookups = 0
    counter = lambda do |*, payload|
      binds = payload[:binds].to_a.map(&:value)
      lookups += 1 if payload[:sql].include?("users") && binds.include?("master@amber.local")
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get messages_path }

    assert_response :success
    assert_equal 1, lookups
  end
end
