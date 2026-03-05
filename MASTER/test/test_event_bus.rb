# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/event_bus"

module MASTER
  class TestEventBus < Minitest::Test
    def setup
      EventBus.clear!
    end

    def teardown
      EventBus.clear!
    end

    def test_subscribe_and_publish
      received = []
      EventBus.subscribe(:test_event) { |data| received << data }
      EventBus.publish(:test_event, value: 42)
      assert_equal 1, received.size
      assert_equal 42, received.first[:value]
    end

    def test_multiple_subscribers
      calls = []
      EventBus.subscribe(:multi) { |_| calls << :first }
      EventBus.subscribe(:multi) { |_| calls << :second }
      EventBus.publish(:multi)
      assert_equal %i[first second], calls
    end

    def test_publish_with_no_subscribers_is_silent
      # Should not raise
      EventBus.publish(:nonexistent_event, foo: "bar")
    end

    def test_handler_error_is_rescued_silently
      EventBus.subscribe(:boom) { |_| raise "handler error" }
      # Should not propagate
      EventBus.publish(:boom)
    end

    def test_unsubscribe_by_subscriber_id
      calls = []
      sub = Object.new
      EventBus.subscribe(:unsub_test, subscriber: sub) { |_| calls << :called }
      EventBus.publish(:unsub_test)
      assert_equal 1, calls.size

      EventBus.unsubscribe(sub)
      EventBus.publish(:unsub_test)
      assert_equal 1, calls.size  # no new calls
    end

    def test_clear_removes_all_subscribers
      EventBus.subscribe(:a) { |_| }
      EventBus.subscribe(:b) { |_| }
      assert_equal 2, EventBus.registered.size
      EventBus.clear!
      assert_equal 0, EventBus.registered.size
    end

    def test_registered_returns_event_names
      EventBus.subscribe(:foo) { |_| }
      EventBus.subscribe(:bar) { |_| }
      names = EventBus.registered
      assert_includes names, :foo
      assert_includes names, :bar
    end

    def test_subscribe_requires_block
      assert_raises(ArgumentError) { EventBus.subscribe(:no_block) }
    end

    def test_string_event_name_converted_to_symbol
      received = []
      EventBus.subscribe("string_event") { |d| received << d }
      EventBus.publish("string_event", x: 1)
      assert_equal 1, received.size
    end

    def test_data_passed_to_handler
      data_received = nil
      EventBus.subscribe(:data_test) { |d| data_received = d }
      EventBus.publish(:data_test, model: "gpt-4", cost: 0.001)
      assert_equal "gpt-4", data_received[:model]
      assert_in_delta 0.001, data_received[:cost]
    end
  end
end
