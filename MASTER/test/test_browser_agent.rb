# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestBrowserAgent < Minitest::Test
  class Governor
    def permit?(*) = Master::Result.ok(true)
  end

  def tool
    Master::Io::BrowserAgent.new(root: Dir.pwd, governor: Governor.new)
  end

  def test_internal_and_non_http_targets_are_refused_before_browser_start
    [
      "http://127.0.0.1/",
      "http://localhost:3000/",
      "http://0.0.0.0/",
      "http://169.254.169.254/latest/meta-data/",
      "file:///etc/passwd",
      "https://user:pass@example.com/",
    ].each do |url|
      result = tool.call(action: "navigate", url:)
      assert result.err?, "#{url} must be refused"
    end
  end

  def test_unknown_actions_and_invalid_session_names_fail_closed
    assert tool.call(action: "delete").err?
    assert tool.call(action: "extract", session: "../outside").err?
  end

  def test_interaction_requires_a_known_operation_and_session
    assert tool.call(action: "interact", operation: "submit", selector: "form").err?
    assert tool.call(action: "interact", operation: "click", selector: "#submit").err?
  end

  def test_browser_interactions_require_fresh_human_consent_even_in_auto_mode
    config = Struct.new(:automatic) { def auto? = automatic }.new(true)
    governor = Master::Fix::Governor.new(config:)
    prompts = []
    Fiber[:master_terminal_ask] = lambda do |prompt:, options:|
      prompts << { prompt:, options: }
      "approve"
    end

    description = "interact set https://example.com selector=#search"
    governor.allow!("browser_agent", description)
    2.times do
      assert governor.permit?("browser_agent", :dangerous, description).ok?
    end

    assert_equal 2, prompts.length
    prompts.each do |request|
      assert_includes request[:prompt], "browser_agent: interact set"
      refute request[:options].any? { |option| option[:value] == "allow" }
    end
  ensure
    Fiber[:master_terminal_ask] = nil
  end

  def test_policy_and_runtime_registration_agree
    root = Master::ROOT
    policy = YAML.safe_load_file(File.join(root, "data", "laws.yml"), aliases: true).fetch("browser_policy")
    assert_equal true, policy.fetch("consent_required")
    assert_includes policy.fetch("write_actions"), "click"
    assert Master::Builder::DEFAULT_TOOL_MAP.key?("BrowserAgent")
    assert_equal Master::Io::LLM::BrowserAgent, Master::Review::LLMDispatcher::LLM_TOOL_MAP.fetch(Master::Io::BrowserAgent)
    tools = YAML.safe_load_file(File.join(root, "data", "tools.yml"), aliases: true)
    assert tools.any? { |row| row["name"] == "BrowserAgent" && row["default"] == true }
  end
end
