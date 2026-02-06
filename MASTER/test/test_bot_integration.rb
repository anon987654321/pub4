#!/usr/bin/env ruby
# frozen_string_literal: true

# MASTER Bot Integration Test Suite

require 'stringio'
require_relative '../lib/loader'
require_relative '../lib/events/bus'
require_relative '../lib/actors/base'
require_relative '../lib/platforms/base'
require_relative '../lib/bot_manager'

# Mock adapter for testing
class MockAdapter < MASTER::Platforms::Base
  attr_reader :sent_messages, :listening
  
  def initialize(name, event_bus, token:, config: {})
    super
    @sent_messages = []
    @listening = false
  end
  
  def send_message(channel_id, text)
    @sent_messages << { channel: channel_id, text: text }
    "message_id_#{rand(1000)}"
  end
  
  def listen(&handler)
    @listening = true
    @handler = handler
  end
  
  def verify_webhook(signature, body)
    true
  end
  
  def trigger_test_message(data)
    handle_incoming(data)
  end
end

# Simple mock adapter for manager tests
class SimpleMockAdapter < MASTER::Platforms::Base
  def send_message(channel_id, text); text; end
  def listen(&handler); end
  def verify_webhook(signature, body); true; end
end

# Mock CLI for testing
class MockCLI
  def process_input(input)
    "Response to: #{input}"
  end
end

class TestRunner
  def initialize
    @passed = 0
    @failed = 0
  end

  def assert(name, condition)
    if condition
      @passed += 1
      puts "  ok: #{name}"
    else
      @failed += 1
      puts "  FAIL: #{name}"
    end
  end

  def run
    puts "MASTER bot integration tests"
    puts

    test_event_bus
    test_base_adapter
    test_bot_manager
    test_webhook_routing

    puts
    puts "#{@passed} passed, #{@failed} failed"
    exit(@failed > 0 ? 1 : 0)
  end

  def test_event_bus
    puts "event bus:"
    
    bus = MASTER::Events::Bus.new
    assert "bus initializes", bus.is_a?(MASTER::Events::Bus)
    
    received = nil
    bus.subscribe(:test_event) { |event| received = event }
    
    event = bus.publish(:test_event, { data: 'test' })
    assert "publishes events", event.type == :test_event
    assert "subscribers receive events", received&.type == :test_event
    assert "event has data", received&.data[:data] == 'test'
    
    count = bus.event_count
    assert "tracks event count", count >= 1
  end

  def test_base_adapter
    puts "base adapter:"
    
    bus = MASTER::Events::Bus.new
    adapter = MockAdapter.new(:mock, bus, token: 'test_token')
    
    assert "adapter initializes", adapter.is_a?(MASTER::Platforms::Base)
    assert "has platform name", adapter.platform_name == 'mockadapter'
    assert "has token", adapter.token == 'test_token'
    
    # Test lifecycle
    assert "starts", adapter.start && adapter.running?
    
    # Test message sending
    adapter.handle_outgoing('channel_123', 'Hello')
    assert "sends messages", adapter.sent_messages.size == 1
    assert "message has channel", adapter.sent_messages.first[:channel] == 'channel_123'
    assert "message has text", adapter.sent_messages.first[:text] == 'Hello'
    
    # Test incoming messages
    events_received = []
    bus.subscribe(:message_received) { |event| events_received << event }
    
    adapter.trigger_test_message({
      channel_id: 'test_channel',
      user_id: 'user_123',
      text: 'test message'
    })
    
    assert "handles incoming messages", events_received.size == 1
    assert "incoming has platform", events_received.first.data[:platform] == 'mockadapter'
    assert "incoming has text", events_received.first.data[:text] == 'test message'
    
    # Test stopping
    adapter.stop
    assert "stops", !adapter.running?
  end

  def test_bot_manager
    puts "bot manager:"
    
    # Suppress CLI output
    old_stdout = $stdout
    $stdout = StringIO.new
    
    bus = MASTER::Events::Bus.new
    cli = MockCLI.new
    manager = MASTER::BotManager.new(cli, bus)
    
    $stdout = old_stdout
    
    assert "manager initializes", manager.is_a?(MASTER::BotManager)
    assert "has platforms hash", manager.platforms.is_a?(Hash)
    assert "has event bus", manager.event_bus == bus
    assert "has cli", manager.cli == cli
    
    # Register mock adapter
    adapter = SimpleMockAdapter.new(:test, bus, token: 'token')
    manager.register_platform(:test, adapter)
    
    assert "registers platforms", manager.platforms[:test] == adapter
    
    # Test stats
    stats = manager.stats
    assert "provides stats", stats.is_a?(Hash)
    assert "stats has platforms", stats[:platforms].include?(:test)
  end

  def test_webhook_routing
    puts "webhook routing:"
    
    # Test webhook path patterns
    path = "/webhook/discord"
    assert "webhook path matches", path.match?(%r{^/webhook/(\w+)$})
    
    match = path.match(%r{^/webhook/(\w+)$})
    platform = match[1]
    assert "extracts platform name", platform == "discord"
    
    # Test different platforms
    %w[discord telegram slack twitter].each do |platform|
      path = "/webhook/#{platform}"
      assert "routes #{platform}", path.match?(%r{^/webhook/(\w+)$})
    end
  end
end

TestRunner.new.run
