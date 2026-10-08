# frozen_string_literal: true

require "test_helper"

# Regression for the "chat saves 200 but nothing ever appears" bug: live delivery
# re-renders _message inside Turbo's broadcast job, where message.conversation and
# message.sender (belongs_to) hit :all strict-loading — dev logs, test/prod raise.
# Message#broadcast_to_logs reloads with those associations and strict loading off,
# so the append renders instead of dying silently.
class MessageBroadcastTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "chat-#{SecureRandom.hex(4)}@brgen.no",
                         password: "password12345", username: "chat_#{SecureRandom.hex(3)}")
    @conversation = Conversation.find_or_create_channel("brgen", city: @city)
    @conversation.participants << @user unless @conversation.participants.include?(@user)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "broadcasting a message is strict-loading safe (was a silent prod raise)" do
    message = Message.create!(conversation: @conversation, sender: @user,
                              content: "hei alle", message_type: "text")
    # broadcast_to_logs re-renders _message the way Turbo's broadcast job does
    # (no request); before the reload fix its conversation.channel? / sender reads
    # raised StrictLoadingViolationError here (dev only logged it, so it shipped).
    assert_nothing_raised { message.send(:broadcast_to_logs) }
  end
end
