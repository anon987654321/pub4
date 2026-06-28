# frozen_string_literal: true

require "test_helper"

class MasterChannelTest < ActionCable::Channel::TestCase
  tests MasterChannel

  test "subscribes to master event streams" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream "master:events"
    assert_has_stream "master:council"
    assert_has_stream "master:status"
  end
end