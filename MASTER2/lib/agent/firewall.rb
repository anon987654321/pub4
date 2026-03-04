# frozen_string_literal: true

require "open3"

module Agent
  class Firewall
    PROTOCOL_NORMALIZATION = {
      "tcp" => "tcp",
      "udp" => "udp",
      "icmp" => "icmp"
    }.freeze

    def initialize(hostname:, logger:, rule_model: FirewallRule)
      @hostname = hostname
      @logger = logger
      @rule_model = rule_model
    end

    def sync!
      rules = load_rules
      persist_rules(rules)
      apply_rules
    end

    def load_rules
      host_id = Host.where(hostname: @hostname).pluck(:id).first
      return [] unless host_id

      @rule_model
        .includes(:host, :service)
        .where(host_id: host_id, enabled: true)
        .order(:position)
        .to_a
    end

    def persist_rules(rules)
      payload = rules.map { |rule| serialize_rule(rule) }
      FirewallState.upsert(
        { hostname: @hostname, rules: payload, updated_at: Time.current },
        unique_by: :hostname
      )
    end

    def apply_rules
      state = FirewallState.where(hostname: @hostname).pluck(:rules).first
      return unless state

      cmd = build_apply_command(state)
      run_command(cmd)
    end

    private

    def serialize_rule(rule)
      protocol = normalize_protocol(rule.protocol)

      service = rule.service
      service_name = service&.name
      port = service&.port

      {
        id: rule.id,
        action: rule.action,
        direction: rule.direction,
        protocol: protocol,
        port: port,
        service: service_name,
        source: rule.source,
        destination: rule.destination,
        position: rule.position
      }
    end

    def normalize_protocol(value)
      key = value.to_s.strip.downcase
      PROTOCOL_NORMALIZATION[key] || key
    end

    def build_apply_command(state)
      json = state.to_json
      [
        "/usr/local/bin/apply-firewall",
        "--hostname", @hostname,
        "--rules", json
      ]
    end

    def run_command(cmd)
      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        @logger.error(
          "Firewall apply failed: hostname=#{@hostname} status=#{status.exitstatus} stderr=#{stderr}"
        )
        raise "Firewall apply failed"
      end

      @logger.info("Firewall applied: hostname=#{@hostname} stdout=#{stdout}")
    rescue Errno::ENOENT => e
      @logger.error("Firewall apply executable missing: #{e.message}")
      raise
    end
  end
end