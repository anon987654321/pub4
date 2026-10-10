# frozen_string_literal: true

require "test_helper"

class MasterMessageReplyJobTest < ActiveSupport::TestCase
  FakeMessenger = Struct.new(:reply_text) do
    def reply(messages:, sender:, message:, session_key:, channel:)
      raise "missing transcript" if messages.empty?
      raise "wrong channel" unless channel == "amber-messenger"
      raise "wrong session" unless session_key.start_with?("amber:")

      reply_text
    end
  end

  test "writes MASTER's reply as a normal message without recursively enqueueing" do
    user = User.strict_loading(false).create!(
      email_address: "master-job-user@example.test", password: "password"
    )
    master = User.master_bot
    incoming = master # reserved bot recipient
    message = user.sent_messages.create!(recipient: incoming, body: "Which jacket works?")

    fake = FakeMessenger.new("The navy one.")
    Shared::MasterMessenger.stub(:new, fake) do
      assert_difference -> { Message.count }, 1 do
        MasterMessageReplyJob.new.perform(message.id)
      end
    end

    reply = Message.order(:created_at).last
    assert_equal master.id, reply.sender_id
    assert_equal user.id, reply.recipient_id
    assert_equal "The navy one.", reply.body
  end

  test "does nothing for messages that are not addressed to MASTER" do
    user = User.strict_loading(false).create!(
      email_address: "ordinary-job-user@example.test", password: "password"
    )
    other = User.strict_loading(false).create!(
      email_address: "ordinary-job-other@example.test", password: "password"
    )
    message = user.sent_messages.create!(recipient: other, body: "hello")

    assert_no_difference -> { Message.count } do
      MasterMessageReplyJob.new.perform(message.id)
    end
  end
end
