# frozen_string_literal: true

require "test_helper"

class ChatServiceConversationTest < ActiveSupport::TestCase
  class FakeStream
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(data)
      @writes << data.to_s
    end

    def close; end
  end

  setup do
    Fiber[:master_conversation] = nil
    @dir = Dir.mktmpdir
    @bus = Master::Trace::EventBus.new(event_log: Master::Trace::Log::Event.new(root: @dir))
    @stream = FakeStream.new
    @mine = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    @service = ChatService.new(
      container: { bus: @bus, session: nil, agent: nil },
      params: { message: "hi" },
      stream: @stream,
      logger: Rails.logger,
      tier: "visitor",
      unlocked: false,
      author: false,
      conversation: @mine,
    )
    @service.send(:subscribe_to_events)
  end

  teardown do
    Fiber[:master_conversation] = nil
    FileUtils.rm_rf(@dir)
  end

  test "sse handlers write this conversation and skip everyone else's" do
    Fiber[:master_conversation] = @mine
    @bus.publish("tool:before", tool: "Write", path: "/tmp/ours.rb")
    ours = @stream.writes.dup

    Fiber[:master_conversation] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    @bus.publish("tool:before", tool: "Write", path: "/tmp/theirs.rb")
    Fiber[:master_conversation] = nil
    @bus.publish("scan:complete", count: 9)

    assert ours.any? { |chunk| chunk.include?("ours.rb") || chunk.include?("Write") }
    assert_equal ours, @stream.writes
    refute @stream.writes.join.include?("theirs.rb")
  end
end
