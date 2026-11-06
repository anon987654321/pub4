# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# Regression for the "chat saves 200 but nothing ever appears" bug: live delivery
# re-renders _message inside Turbo's broadcast job, where message.conversation and
# message.sender (belongs_to) hit :all strict-loading — dev logs, test/prod raise.
# Message#broadcast_to_logs reloads with those associations and strict loading off,
# so the append renders instead of dying silently.
class MessageBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

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

  def direct_with(other)
    Conversation.find_or_create_direct(@user, other)
  end

  def other_user
    User.create!(email_address: "peer-#{SecureRandom.hex(4)}@brgen.no",
                 password: "password12345", username: "peer_#{SecureRandom.hex(3)}")
  end

  # One render goes to everyone in the thread, so it may not be the sender's
  # view of the line: it carries the sender's controls and the others' controls,
  # each marked, and the log controller keeps the viewer's own.
  test "a broadcast line is the same for every viewer, with each control marked for whom" do
    conversation = direct_with(other_user)

    Current.session = @user.sessions.create! if Current.respond_to?(:session=) && @user.respond_to?(:sessions)
    streams = capture_turbo_stream_broadcasts(conversation) do
      Message.create!(conversation:, sender: @user, content: "hei", message_type: "text")
    end
    html = streams.last.to_html
    assert_includes html, 'data-for="sender"', "edit and unsend reach the sender's own copy"
    assert_includes html, 'data-for="others"', "report reaches the recipients"
    assert_includes html, 'data-from="peer"', "nobody is the viewer in a broadcast"
  ensure
    Current.reset
  end

  test "an edit and an unsend replace the line in every open thread" do
    conversation = direct_with(other_user)
    message = Message.create!(conversation:, sender: @user, content: "skrivefeil", message_type: "text")

    edited = capture_turbo_stream_broadcasts(conversation) { message.edit!("rettet") }
    assert_equal "replace", edited.last["action"]
    assert_includes edited.last.to_html, "rettet"

    unsent = capture_turbo_stream_broadcasts(conversation) { message.reload.unsend! }
    assert_equal "replace", unsent.last["action"]
    refute_includes unsent.last.to_html, "rettet"
  end

end
