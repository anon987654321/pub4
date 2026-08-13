# frozen_string_literal: true

require_relative "test_helper"

class TestToolProfile < Minitest::Test
  def teardown
    Fiber[:master_visitor] = nil
    Fiber[:master_paired] = nil
    Fiber[:master_elevated] = nil
  end

  def test_visitor_without_pairing_is_public
    Fiber[:master_visitor] = true
    Fiber[:master_paired] = nil

    assert_equal :public, Master::Ground::ToolProfile.current
    assert Master::Ground::ToolProfile.allow?("AskLlm")
    refute Master::Ground::ToolProfile.allow?("WebFetch")
    refute Master::Ground::ToolProfile.allow?("Shell")
  end

  def test_paired_visitor_is_messaging
    Fiber[:master_visitor] = true
    Fiber[:master_paired] = true

    assert_equal :messaging, Master::Ground::ToolProfile.current
    assert Master::Ground::ToolProfile.allow?("WebFetch")
    assert Master::Ground::ToolProfile.allow?("MemoryRecord")
    refute Master::Ground::ToolProfile.allow?("Shell")
    refute Master::Ground::ToolProfile.allow?("WriteFile")
  end

  def test_authenticated_is_full
    Fiber[:master_visitor] = false
    Fiber[:master_paired] = nil

    assert_equal :full, Master::Ground::ToolProfile.current
    assert_nil Master::Ground::ToolProfile.allowlist
    assert Master::Ground::ToolProfile.allow?("ReadFile")
  end

  def test_session_note_names_the_scope
    Fiber[:master_visitor] = true
    assert_match(/public visitor/, Master::Ground::ToolProfile.session_note)

    Fiber[:master_paired] = true
    assert_match(/paired messaging/, Master::Ground::ToolProfile.session_note)
  end

  def test_yaml_profiles_are_the_allowlists
    public = Master::Ground::ToolProfile.public_names
    messaging = Master::Ground::ToolProfile.messaging_names

    assert_equal %w[AskLlm WebSearch SubdomainOrchestrator], public
    assert_includes messaging, "WebFetch"
    assert_includes messaging, "MemoryRecord"
  end
end
