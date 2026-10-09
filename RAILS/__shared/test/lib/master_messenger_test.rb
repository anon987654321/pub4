# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/master_messenger"

class MasterMessengerTest < Minitest::Test
  Client = Struct.new(:calls) do
    def turn(message, session_key:, channel:)
      calls << { message:, session_key:, channel: }
      { "ok" => true, "output" => "answer" }
    end
  end

  Sender = Struct.new(:display_name)
  Message = Struct.new(:sender, :body)

  def test_master_client_is_called_with_context_keywords
    client = Client.new([])
    sender = Sender.new("Ada")
    latest = Message.new(sender, "ping")

    Shared::MasterMessenger.new(client:).reply(
      messages: [latest], sender:, message: latest,
      session_key: "amber:1-2", channel: "amber-messenger"
    )

    call = client.calls.fetch(0)
    assert_equal "amber:1-2", call.fetch(:session_key)
    assert_equal "amber-messenger", call.fetch(:channel)
  end

  def test_uses_one_shared_ingress_contract
    client = Client.new([])
    sender = Sender.new("Ada")
    latest = Message.new(sender, "What changed?")
    prior = Message.new(sender, "hello")
    conversation = [prior, latest]
    result = Shared::MasterMessenger.new(client:).reply(
      messages: conversation, sender:, message: latest,
      session_key: "brgen:conversation:1", channel: "messenger"
    )

    assert_equal "answer", result
    assert_equal "brgen:conversation:1", client.calls.first[:session_key]
    assert_equal "messenger", client.calls.first[:channel]
    assert_includes client.calls.first[:message], "What changed?"
    assert_includes client.calls.first[:message], "Ada: hello"
  end
end
