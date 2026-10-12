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

      source = File.join(root, "lib", "io", "browser_agent.rb")
      return failure("BrowserAgent tool missing") unless File.file?(source)

      content = File.read(source)
      evasion_patterns = /navigator\.webdriver|AutomationControlled|browse_randomly|humanize_mouse|stealth_script|user_agents\s*:/i
      browser_config = File.join(root, "data", "browser_agents.yml")
      sources = [content, (File.read(browser_config) if File.file?(browser_config))].compact
      if sources.any? { |text| text.match?(evasion_patterns) }
        return failure("BrowserAgent must not disguise automation or simulate random browsing")
      end
      %w[SsrfGuard.pinned_address secure_page :dangerous].each do |guard|
        return failure("BrowserAgent security guard missing: #{guard}") unless content.include?(guard)
      end
      return failure("BrowserAgent interaction consent boundary missing") unless content.include?('interact #{op}')

      llm_tool = File.read(File.join(root, "lib", "io", "llm.rb"))
      unless llm_tool.include?("fresh human approval") && llm_tool.include?("recipient consent") && llm_tool.include?("Do not disguise automation")
        return failure("BrowserAgent model-facing consent policy missing")
      end
      return failure("BrowserAgent session limit disagrees with policy") unless content.include?("MAX_SESSIONS = #{policy["max_sessions"]}")

      governor = File.read(File.join(root, "lib", "fix", "governor.rb"))
      %w[human_consent_required? consent_required @auto].each do |guard|
        return failure("Governor consent boundary missing: #{guard}") unless governor.include?(guard)
      end

      tools = YAML.safe_load_file(File.join(root, "data", "tools.yml"), aliases: true)
      registered = Array(tools).any? { |tool| tool["name"] == "BrowserAgent" && tool["default"] == true }
      return failure("BrowserAgent must be registered and enabled") unless registered

      GateResult.new.checked!
    rescue StandardError => e
      GateResult.from_error(e, gate: "browser_policy")
    end
  end
end
