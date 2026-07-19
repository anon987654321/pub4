# frozen_string_literal: true

require_relative "test_helper"

class TestSmokeChatProbe < Minitest::Test
  def test_smoke_chat_bypasses_container_warmup
    app = File.read(File.join(Master::ROOT, "web", "app", "controllers", "application_controller.rb"))
    chat = File.read(File.join(Master::ROOT, "web", "app", "controllers", "chat_controller.rb"))
    assert_includes app, "smoke_chat_probe?"
    assert_includes chat, "stream_smoke_reply"
    assert_includes chat, "ping"
  end
end