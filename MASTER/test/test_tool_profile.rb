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

    assert_equal :public, Master::Ground::Tool::Profile.current
    assert Master::Ground::Tool::Profile.allow?("AskLlm")
    refute Master::Ground::Tool::Profile.allow?("WebFetch")
    refute Master::Ground::Tool::Profile.allow?("Shell")
  end

  def test_paired_visitor_is_messaging
    Fiber[:master_visitor] = true
    Fiber[:master_paired] = true

    assert_equal :messaging, Master::Ground::Tool::Profile.current
    assert Master::Ground::Tool::Profile.allow?("WebFetch")
    assert Master::Ground::Tool::Profile.allow?("MemoryRecord")
    refute Master::Ground::Tool::Profile.allow?("Shell")
    refute Master::Ground::Tool::Profile.allow?("WriteFile")
  end

  def test_authenticated_is_full
    Fiber[:master_visitor] = false
    Fiber[:master_paired] = nil

    assert_equal :full, Master::Ground::Tool::Profile.current
    assert_nil Master::Ground::Tool::Profile.allowlist
    assert Master::Ground::Tool::Profile.allow?("ReadFile")
  end

  def test_session_note_names_the_scope
    Fiber[:master_visitor] = true
    assert_match(/public visitor/, Master::Ground::Tool::Profile.session_note)

    Fiber[:master_paired] = true
    assert_match(/paired messaging/, Master::Ground::Tool::Profile.session_note)
  end

  def test_yaml_profiles_are_the_allowlists
    public = Master::Ground::Tool::Profile.public_names
    messaging = Master::Ground::Tool::Profile.messaging_names

    assert_equal %w[AskLlm WebSearch SubdomainOrchestrator], public
    assert_includes messaging, "WebFetch"
    assert_includes messaging, "MemoryRecord"
  end
end
