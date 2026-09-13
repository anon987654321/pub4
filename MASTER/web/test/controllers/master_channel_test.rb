# frozen_string_literal: true

require "test_helper"

class MasterChannelTest < ActionCable::Channel::TestCase
  tests MasterChannel

  test "subscribes to the one stream cable_bridge broadcasts" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream "master:events"
    assert_equal ["master:events"], subscription.streams
  end
end
