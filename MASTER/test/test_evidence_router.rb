# frozen_string_literal: true

require_relative "test_helper"

class TestEvidenceRouter < Minitest::Test
  Router = Master::Ground::EvidenceRouter

  def test_routes_current_questions_to_web
    assert_equal :web_current, Router.classify("What is the latest Telegram Bot API?")
    assert Router.web_required?(:web_current)
  end

  def test_routes_explicit_research_to_deep_research
    assert_equal :deep_research, Router.classify("Research TDLib and compare the sources.")
    assert Router.web_required?(:deep_research)
  end

  def test_routes_repository_questions_to_files
    assert_equal :repository, Router.classify("Read MASTER/lib/core.rb and explain the fold.")
  end

  def test_routes_browser_and_device_questions_to_capabilities
    assert_equal :browser, Router.classify("Open the Snapchat website and inspect the account page.")
    assert_equal :device, Router.classify("Scan nearby Wi-Fi and Bluetooth devices on Android.")
  end

  def test_unknown_factual_questions_get_an_evidence_prompt
    assert_equal :unknown, Router.classify("How does this obscure protocol work?")
    assert_match(/do not answer from memory/, Router.prompt_for(:unknown))
  end
end
