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
    choices = %w[allow approve approve]
    Fiber[:master_terminal_ask] = lambda do |prompt:, options:|
      prompts << { prompt:, options: }
      choices.shift
    end

    description = "interact set https://example.com selector=#search"
    governor.allow!("browser", description)
    assert governor.permit?("browser", :dangerous, description).err?,
           "a remembered allow response must not count as fresh consent"
    2.times do
      assert governor.permit?("browser", :dangerous, description).ok?
    end

    assert_equal 3, prompts.length
    prompts.each do |request|
      assert_includes request[:prompt], "browser: interact set"
      refute request[:options].any? { |option| option[:value] == "allow" }
    end
  ensure
    Fiber[:master_terminal_ask] = nil
  end

  def test_status_works_without_opening_a_browser
    result = tool.call(action: "status")
    assert result.ok?
    assert_includes result.value!, "browser ready"
  end

  def test_look_follow_and_paginate_fail_closed_without_a_session
    assert tool.call(action: "look").err?
    assert tool.call(action: "follow", selector: "a").err?
    assert tool.call(action: "paginate").err?
  end

  def test_navigation_session_is_locked_to_its_first_host_and_mode
    agent = tool
    sessions = agent.instance_variable_get(:@sessions)
    state = Master::Io::BrowserAgent::Session.new(
      browser: nil,
      page: nil,
      mutex: Mutex.new,
      host: "example.com",
      headless: false,
    )
    sessions["default"] = state

    assert_equal false, agent.send(:headless_for_navigation, "default"),
                 "navigation after visible login must keep the visible browser"
    sessions.delete("default")
    assert_equal true, agent.send(:headless_for_navigation, "default"),
                 "new navigation sessions should remain headless by default"
    sessions["default"] = state

    assert agent.send(:ensure_session_host!, state, URI("https://EXAMPLE.com/next"))
    assert_raises(ArgumentError) do
      agent.send(:ensure_session_host!, state, URI("https://other.example/"))
    end
    assert_raises(ArgumentError) do
      agent.send(:ensure_session_host!, state, URI("file:///etc/passwd"))
    end
    assert_raises(ArgumentError) do
      agent.send(:open_session, "default", host: "example.com", headless: true)
    end
  end

  def test_pagination_output_has_a_hard_byte_budget
    assert_equal 128 * 1024, Master::Io::BrowserAgent::MAX_PAGINATION_OUTPUT_BYTES
  end

  def test_shared_transport_can_enforce_a_session_host
    transport = Master::Io::WebBrowse.new(governor: Governor.new)
    assert transport.send(:request_allowed_for_host?, URI("https://example.com/page"), "example.com")
    assert transport.send(:request_allowed_for_host?, URI("https://EXAMPLE.COM/page"), "example.com")
    assert transport.send(:request_allowed_for_host?, URI("https://www.example.com/page"), "example.com")
    assert transport.send(:request_allowed_for_host?, URI("https://EXAMPLE.COM./page"), "example.com")
    refute transport.send(:request_allowed_for_host?, URI("https://other.example/page"), "example.com")
  end

  def test_policy_and_runtime_registration_agree
    root = Master::ROOT
    policy = Master.load_yaml(File.join(root, "data", "laws.yml")).fetch("browser_policy")
    assert_equal true, policy.fetch("consent_required")
    assert_includes policy.fetch("write_actions"), "click"
    assert_equal %w[status navigate login extract look follow paginate close], policy.fetch("read_actions")
    assert_equal true, policy.fetch("session_host_bound")
    assert_equal true, policy.fetch("screenshot_evidence_required")
    assert_equal 500, policy.fetch("max_capture_files")
    assert_equal 50, policy.fetch("max_pagination_pages")
    assert_equal 131_072, policy.fetch("max_pagination_output_bytes")
    assert_equal true, policy.fetch("follow_anchors_by_href_only")
    assert_equal "blocked", policy.fetch("visible_login_submission")
    interactions = policy.fetch("external_interactions")
    assert_equal true, interactions.fetch("ai_identity_disclosure_required")
    assert_equal true, interactions.fetch("recipient_consent_required")
    assert_equal true, interactions.fetch("recipient_opt_out_required")
    assert_equal true, interactions.fetch("per_action_human_approval_required")
    assert_equal "forbidden", interactions.fetch("unsolicited_bulk_outreach")
    assert_equal "forbidden", interactions.fetch("autonomous_message_sending")
    assert_equal "forbidden", interactions.fetch("browser_fingerprint_spoofing")
    assert_equal "forbidden", interactions.fetch("platform_evasion")
    assert Master::Builder::DEFAULT_TOOL_MAP.key?("Browser")
    assert_equal Master::Io::LLM::Browser, Master::Review::LLMDispatcher::LLM_TOOL_MAP.fetch(Master::Io::BrowserAgent)
    tools = Master.load_yaml(File.join(root, "data", "tools.yml"))
    assert tools.any? { |row| row["name"] == "Browser" && row["default"] == true }
  end
end
