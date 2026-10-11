# frozen_string_literal: true

require "yaml"

module Deploy
  class BrowserPolicyGate
    REQUIRED_HOSTS = %w[127.0.0.1 localhost 0.0.0.0 169.254.169.254].freeze
    REQUIRED_ACTIONS = %w[click set type].freeze

    def self.run
      root = Master::ROOT
      policy = YAML.safe_load_file(File.join(root, "data", "laws.yml"), aliases: true).fetch("browser_policy")
      missing_hosts = REQUIRED_HOSTS - Array(policy["forbidden_hosts"]).map { |host| host.to_s.downcase }
      return GateResult.fail("browser policy missing forbidden hosts: #{missing_hosts.join(", ")}") unless missing_hosts.empty?
      missing_actions = REQUIRED_ACTIONS - Array(policy["write_actions"]).map(&:to_s)
      return GateResult.fail("browser policy missing write actions: #{missing_actions.join(", ")}") unless missing_actions.empty?
      return GateResult.fail("browser write consent must be required") unless policy["consent_required"] == true
      methods = Array(policy["allowed_network_methods"]).map { |method| method.to_s.upcase }
      return GateResult.fail("browser policy must allow only GET/HEAD browser requests") unless methods.sort == %w[GET HEAD]
      return GateResult.fail("browser session limit must be four") unless policy["max_sessions"] == 4

      source = File.join(root, "lib", "io", "browser_agent.rb")
      return GateResult.fail("BrowserAgent tool missing") unless File.file?(source)

      content = File.read(source)
      %w[SsrfGuard.pinned_address secure_page :dangerous].each do |guard|
        return GateResult.fail("BrowserAgent security guard missing: #{guard}") unless content.include?(guard)
      end
      return GateResult.fail("BrowserAgent interaction consent boundary missing") unless content.include?('interact #{op}')
      return GateResult.fail("BrowserAgent session limit disagrees with policy") unless content.include?("MAX_SESSIONS = #{policy["max_sessions"]}")

      governor = File.read(File.join(root, "lib", "fix", "governor.rb"))
      %w[human_consent_required? consent_required @auto].each do |guard|
        return GateResult.fail("Governor consent boundary missing: #{guard}") unless governor.include?(guard)
      end

      tools = YAML.safe_load_file(File.join(root, "data", "tools.yml"), aliases: true)
      registered = Array(tools).any? { |tool| tool["name"] == "BrowserAgent" && tool["default"] == true }
      return GateResult.fail("BrowserAgent must be registered and enabled") unless registered

      GateResult.pass("browser policy intact")
    rescue StandardError => e
      GateResult.fail("browser policy gate error: #{e.class}: #{e.message}")
    end
  end
end
