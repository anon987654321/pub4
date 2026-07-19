# frozen_string_literal: true

require_relative "test_helper"

class TestChatSseContract < Minitest::Test
  WEB_ROOT = File.join(Master::ROOT, "web")

  def test_chat_service_smoke_messages
    source = File.read(File.join(WEB_ROOT, "app", "services", "chat_service.rb"))
    assert_includes source, 'SMOKE_MESSAGES = %w[ping pong health up]'
    assert_includes source, "data: [DONE]"
  end

  def test_message_action_sets_sse_headers
    source = File.read(File.join(WEB_ROOT, "app", "controllers", "chat_controller.rb"))
    assert_includes source, "text/event-stream"
    assert_includes source, "ChatService.new"
  end
end
