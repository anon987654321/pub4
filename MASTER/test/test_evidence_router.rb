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
    assert_equal :browser, Router.classify("Open the FetLife website and inspect the account page.")
    assert_equal :device, Router.classify("Scan nearby Wi-Fi and Bluetooth devices on Android.")
  end

  def test_personal_support_stories_are_minimized_before_external_research
    story = "I am scared because my boyfriend Alex checks my phone and controls my money. Research whether this is coercive control."
    query = Router.web_search_query(story)

    assert_includes query, "coercive control"
    assert_includes query, "safety planning"
    refute_includes query, "Alex"
    refute_includes query, "my boyfriend"
    refute_includes query, "checks my phone"
    refute_includes query, "controls my money"
  end

  def test_technical_ai_therapist_research_keeps_its_requested_topic
    request = "How can MASTER improve its AI therapist prompt? Research GitHub and ar5iv."

    assert_equal request, Router.web_search_query(request)
  end

  def test_nonpersonal_current_search_keeps_the_original_query
    request = "What is the latest Telegram Bot API?"

    assert_equal request, Router.web_search_query(request)
  end

  def test_questions_about_master_itself_are_answered_from_the_repository
    assert_equal :repository, Router.classify("why aren't you reading tts out loud?")
    assert_equal :repository, Router.classify("what does /fix do by default?")
    assert_equal :repository, Router.classify("how do your skills get loaded?")
    assert_equal :unknown, Router.classify("how does this obscure protocol work?")
    assert_equal :conversation, Router.classify("hello")
  end

  def test_unknown_questions_are_told_to_inspect_the_project_too
    assert_match(/inspect them with your tools/, Router.prompt_for(:unknown))
  end

  def test_unknown_factual_questions_get_an_evidence_prompt
    assert_equal :unknown, Router.classify("How does this obscure protocol work?")
    assert_match(/do not answer from memory/, Router.prompt_for(:unknown))
  end

  # A turn labelled casual still has an evidence route; its rule has to reach the prompt.
  class CasualHost
    include Master::Review::Agent::PromptBuilder

    Config = Struct.new(:task_type) do
      def [](key) = key == "root" ? "/work/pub4" : nil
    end
    Session = Struct.new(:messages, :topic)

    def initialize = (@config = Config.new("chat"); @session = Session.new([{ role: :user, content: "why no tts?" }], nil))
    def prompt = casual_dynamic_prompt
  end

  def test_the_casual_prompt_carries_the_evidence_rule_and_the_working_directory
    Fiber[:master_evidence_note] = Router.prompt_for(:repository)
    out = CasualHost.new.prompt

    assert_includes out, "this turn concerns the repository"
    assert_includes out, "Working in /work/pub4"
  ensure
    Fiber[:master_evidence_note] = nil
  end
end
