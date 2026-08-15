# frozen_string_literal: true

require_relative "test_helper"

class TestEventBus < Minitest::Test
  def setup
    Fiber[:master_conversation] = nil
    @dir = Dir.mktmpdir
    @bus = Master::Trace::EventBus.new(
      event_log: Master::Trace::EventLog.new(root: @dir),
    )
  end

  def teardown
    Fiber[:master_conversation] = nil
    FileUtils.rm_rf(@dir)
  end

  def test_publish_stamps_the_fiber_conversation
    seen = nil
    @bus.subscribe("tool:before") { |ev| seen = ev }
    Fiber[:master_conversation] = "aabbccddeeff00112233445566778899"
    @bus.publish("tool:before", tool: "Write")

    assert_equal "aabbccddeeff00112233445566778899", seen[:conversation]
    assert_equal "Write", seen[:tool]
  end

  def test_publish_omits_conversation_when_the_fiber_is_unset
    seen = nil
    @bus.subscribe("tool:before") { |ev| seen = ev }
    @bus.publish("tool:before", tool: "Write")

    refute seen.key?(:conversation)
  end

  def test_a_handler_can_tell_this_conversation_from_another
    mine = []
    @bus.subscribe("tool:before") do |ev|
      next unless ev[:conversation] == "mine-conv"

      mine << ev[:path]
    end

    Fiber[:master_conversation] = "mine-conv"
    @bus.publish("tool:before", path: "ours.rb")
    Fiber[:master_conversation] = "other-conv"
    @bus.publish("tool:before", path: "theirs.rb")
    Fiber[:master_conversation] = nil
    @bus.publish("tool:before", path: "background.rb")

    assert_equal ["ours.rb"], mine
  end
end
