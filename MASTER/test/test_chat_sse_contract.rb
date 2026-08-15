# frozen_string_literal: true

require_relative "test_helper"

class TestChatSseContract < Minitest::Test
  WEB_ROOT = File.join(Master::ROOT, "web")

  def test_chat_service_smoke_messages
    source = File.read(File.join(WEB_ROOT, "app", "services", "chat_service.rb"))
    assert_includes source, "SMOKE_MESSAGES = %w[ping pong health up]"
    assert_includes source, "data: [DONE]"
  end

  def test_chat_service_forwards_uploaded_images_into_the_turn
    source = File.read(File.join(WEB_ROOT, "app", "services", "chat_service.rb"))
    assert_includes source, "image: image_payload"
    assert_includes source, "def image_payload"
  end

  def test_chat_service_sse_handlers_are_keyed_to_this_conversation
    source = File.read(File.join(WEB_ROOT, "app", "services", "chat_service.rb"))
    assert_includes source, "next unless mine && ev[:conversation] == mine"
  end

  def test_message_action_sets_sse_headers
    source = File.read(File.join(WEB_ROOT, "app", "controllers", "chat_controller.rb"))
    assert_includes source, "text/event-stream"
    assert_includes source, "ChatService.new"
  end

  def test_enhance_runs_under_the_visitor_fiber
    source = File.read(File.join(WEB_ROOT, "app", "controllers", "chat_controller.rb"))
    enhance = source[/def enhance\n.*?\n  end/m]
    assert enhance, "enhance action missing"
    assert_includes enhance, "with_master_fiber"
  end

  def test_cable_rejects_an_empty_web_token
    source = File.read(File.join(WEB_ROOT, "app", "channels", "application_cable", "connection.rb"))
    assert_includes source, "return false if tok.empty?"
    refute_includes source, "return true if tok.empty?"
  end
end
