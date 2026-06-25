# frozen_string_literal: true

require_relative "test_helper"

class TestSmokeChatProbe < Minitest::Test
  def test_warming_exempt_includes_smoke_chat
    source = File.read(File.join(Master::ROOT, "web", "app", "controllers", "application_controller.rb"))
    assert_includes source, "smoke_chat_probe?"
    assert_includes source, "SMOKE_CHAT_MESSAGES"
    assert_includes source, "ping"
  end
end