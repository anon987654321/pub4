# frozen_string_literal: true

require "test_helper"

class MasterChannelTest < ActiveSupport::TestCase
  test "subscribes to master event streams" do
    channel = MasterChannel.new(nil, {})
    streams = []
    channel.define_singleton_method(:stream_from) { |name| streams << name }

    channel.subscribed

    assert_includes streams, "master:events"
    assert_includes streams, "master:council"
    assert_includes streams, "master:status"
  end
end