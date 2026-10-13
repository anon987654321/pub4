# frozen_string_literal: true

require "yaml"

module Deploy
  class BrowserPolicyGate
    REQUIRED_HOSTS = %w[127.0.0.1 localhost 0.0.0.0 169.254.169.254].freeze
    REQUIRED_ACTIONS = %w[click set type].freeze
    REQUIRED_INTERACTION_POLICY = {
      "ai_identity_disclosure_required" => true,
      "recipient_consent_required" => true,
      "recipient_opt_out_required" => true,
      "per_action_human_approval_required" => true,
      "unsolicited_bulk_outreach" => "forbidden",
      "autonomous_message_sending" => "forbidden",
      "browser_fingerprint_spoofing" => "forbidden",
      "platform_evasion" => "forbidden",
    }.freeze

    def self.failure(message)
      GateResult.new.tap { |result| result.fail(message) }
    end

    def self.run
      root = Master::ROOT
      policy = YAML.safe_load_file(File.join(root, "data", "laws.yml"), aliases: true).fetch("browser_policy")
      missing_hosts = REQUIRED_HOSTS - Array(policy["forbidden_hosts"]).map { |host| host.to_s.downcase }
      return failure("browser policy missing forbidden hosts: #{missing_hosts.join(", ")}") unless missing_hosts.empty?
      missing_actions = REQUIRED_ACTIONS - Array(policy["write_actions"]).map(&:to_s)
      return failure("browser policy missing write actions: #{missing_actions.join(", ")}") unless missing_actions.empty?
      return failure("browser write consent must be required") unless policy["consent_required"] == true
      interactions = policy["external_interactions"]
      return failure("browser external interaction policy missing") unless interactions.is_a?(Hash)
      REQUIRED_INTERACTION_POLICY.each do |key, expected|
        return failure("browser external interaction policy #{key} must be #{expected}") unless interactions[key] == expected
      end
      methods = Array(policy["allowed_network_methods"]).map { |method| method.to_s.upcase }
      return failure("browser policy must allow only GET/HEAD browser requests") unless methods.sort == %w[GET HEAD]
      return failure("browser session limit must be four") unless policy["max_sessions"] == 4
      read_actions = Array(policy["read_actions"]).map(&:to_s)
      required_read_actions = %w[status navigate login extract look follow paginate close]
      missing_read_actions = required_read_actions - read_actions
      return failure("browser policy missing read actions: #{missing_read_actions.join(", ")}") unless missing_read_actions.empty?
      return failure("browser sessions must be host-bound") unless policy["session_host_bound"] == true
      return failure("browser screenshots must be evidence") unless policy["screenshot_evidence_required"] == true
      return failure("browser capture cap must be 500") unless policy["max_capture_files"] == 500
      return failure("browser page limit must be 50") unless policy["max_pagination_pages"] == 50
      return failure("browser pagination output budget must be 128 KiB") unless policy["max_pagination_output_bytes"] == 131_072
      return failure("browser anchor navigation must use hrefs") unless policy["follow_anchors_by_href_only"] == true
      return failure("visible login must preserve the read-only boundary") unless policy["visible_login_submission"] == "blocked"

      source = File.join(root, "lib", "io", "browser_agent.rb")
      return failure("BrowserAgent tool missing") unless File.file?(source)

      content = File.read(source)
      return failure("visible login must disclose blocked POST submissions") unless content.include?("ordinary POST-based login submissions are blocked")
      evasion_patterns = /navigator\.webdriver|AutomationControlled|browse_randomly|humanize_mouse|stealth_script|user_agents\s*:/i
      browser_config = File.join(root, "data", "browser_agents.yml")
      sources = [content, (File.read(browser_config) if File.file?(browser_config))].compact
      if sources.any? { |text| text.match?(evasion_patterns) }
        return failure("BrowserAgent must not disguise automation or simulate random browsing")
      end
      %w[SsrfGuard.pinned_address secure_page :dangerous ensure_session_host! target_from_anchor! save_screenshot(state) MAX_PAGINATION_OUTPUT_BYTES].each do |guard|
        return failure("BrowserAgent security or capability guard missing: #{guard}") unless content.include?(guard)
      end
      return failure("BrowserAgent interaction consent boundary missing") unless content.include?('interact #{op}')
      return failure("BrowserAgent capture limit disagrees with policy") unless content.include?("MAX_CAPTURES = #{policy["max_capture_files"]}")
      return failure("BrowserAgent page limit disagrees with policy") unless content.include?("clamp(1, #{policy["max_pagination_pages"]})")
      return failure("BrowserAgent output limit disagrees with policy") unless content.include?("MAX_PAGINATION_OUTPUT_BYTES = #{policy["max_pagination_output_bytes"] / 1024} * 1024")
      required_transport = File.join(root, "lib", "io", "web_browse.rb")
      transport = File.read(required_transport)
      %w[request_allowed_for_host? allowed_host reset_page_budget].each do |guard|
        return failure("WebBrowse host-bound transport missing: #{guard}") unless transport.include?(guard)
      end

      llm_tool = File.read(File.join(root, "lib", "io", "llm.rb"))
      %w[status navigate login extract look follow paginate close].each do |action|
        return failure("BrowserAgent model-facing action missing: #{action}") unless llm_tool.include?(action)
      end
      unless llm_tool.include?("fresh human approval") && llm_tool.include?("recipient consent") && llm_tool.include?("Do not disguise automation")
        return failure("BrowserAgent model-facing consent policy missing")
      end
      return failure("BrowserAgent session limit disagrees with policy") unless content.include?("MAX_SESSIONS = #{policy["max_sessions"]}")

      governor = File.read(File.join(root, "lib", "fix", "governor.rb"))
      %w[human_consent_required? consent_required @auto].each do |guard|
        return failure("Governor consent boundary missing: #{guard}") unless governor.include?(guard)
      end

      tools = YAML.safe_load_file(File.join(root, "data", "tools.yml"), aliases: true)
      registered = Array(tools).any? { |tool| tool["name"] == "Browser" && tool["default"] == true }
      return failure("Browser must be registered and enabled") unless registered

      GateResult.new.checked!
    rescue StandardError => e
      GateResult.from_error(e, gate: "browser_policy")
    end
  end
end
