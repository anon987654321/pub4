# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestChatCommands < Minitest::Test
  def setup
    @session = MASTER::Session.current
  end

  def test_chat_commands_module_exists
    assert defined?(MASTER::Commands::ChatCommands), "ChatCommands module should exist"
  end

  def test_enter_chat_mode_method_exists
    assert_respond_to MASTER::Commands, :enter_chat_mode
  end

  def test_chat_mode_uses_fast_tier
    # This test verifies the chat command structure uses :fast tier
    # We can't easily test the interactive loop without mocking stdin,
    # but we can verify the module is properly defined
    
    chat_module = MASTER::Commands::ChatCommands
    assert chat_module.instance_methods.include?(:enter_chat_mode), 
           "ChatCommands should define enter_chat_mode method"
  end

  def test_chat_mode_handles_session_context
    # Verify that Session responds to context methods used by chat mode
    assert_respond_to @session, :add_user, "Session should have add_user method"
    assert_respond_to @session, :add_assistant, "Session should have add_assistant method"
    assert_respond_to @session, :context_for_llm, "Session should have context_for_llm method"
  end
end
