# frozen_string_literal: true

module Agent
  class Firewall
    ALLOWED_PROTOCOLS = %w[tcp udp icmp].freeze
    DEFAULT_ACTION = "deny"

    def initialize(options = {})
      @logger = options.fetch(:logger, nil)
      @dry_run = options.fetch(:dry_run, false)
      @default_action = options.fetch(:default_action, DEFAULT_ACTION)
    end

    def apply(server_id:, rules_params:)
      rules = sanitize(rules_params)
      persist_rules(server_id, rules)
      configure_system_firewall(server_id) unless @dry_run
      true
    end

    def sanitize(rules_params)
      rules = normalize_rules(rules_params)
      rules = rules.map { |r| normalize_rule_keys(r) }
      rules = rules.map { |r| normalize_protocol(r) }
      rules = rules.map { |r| normalize_ports(r) }
      rules = rules.map { |r| normalize_action(r) }
      rules.select { |r| valid_rule?(r) }
    end

    private

    def normalize_rules(rules_params)
      return [] if rules_params.nil?
      return rules_params if rules_params.is_a?(Array)

      [rules_params]
    end

    def normalize_rule_keys(rule)
      rule = rule.to_h
      {
        protocol: rule.fetch(:protocol, rule.fetch("protocol", nil)),
        port: rule.fetch(:port, rule.fetch("port", nil)),
        port_range: rule.fetch(:port_range, rule.fetch("port_range", nil)),
        source: rule.fetch(:source, rule.fetch("source", nil)),
        action: rule.fetch(:action, rule.fetch("action", nil)),
        comment: rule.fetch(:comment, rule.fetch("comment", nil))
      }
    end

    def normalize_protocol(rule)
      proto = rule.fetch(:protocol, nil)
      rule.merge(protocol: proto.to_s.downcase)
    end

    def normalize_ports(rule)
      port = rule.fetch(:port, nil)
      range = rule.fetch(:port_range, nil)

      rule = rule.merge(port: normalize_int(port))
      rule.merge(port_range: normalize_range(range))
    end

    def normalize_action(rule)
      action = rule.fetch(:action, nil)
      action = @default_action if action.nil?
      rule.merge(action: action.to_s.downcase)
    end

    def normalize_int(value)
      return nil if value.nil?
      return value if value.is_a?(Integer)

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_range(value)
      return nil if value.nil?
      return value if value.is_a?(Range)

      parts = value.to_s.split("-", 2).map { |p| normalize_int(p) }
      return nil unless parts.length == 2 && parts.all?

      (parts[0]..parts[1])
    end

    def valid_rule?(rule)
      proto = rule.fetch(:protocol, nil)
      return false if proto.nil?
      return false unless ALLOWED_PROTOCOLS.include?(proto)

      action = rule.fetch(:action, nil)
      return false if action.nil?

      port = rule.fetch(:port, nil)
      range = rule.fetch(:port_range, nil)
      return true if proto == "icmp"
      return false if port.nil? && range.nil?

      true
    end

    def persist_rules(server_id, rules)
      server = ::Server.find(server_id)

      existing = server.firewall_rules.includes(:server, :network_interface).to_a
      existing_by_sig = existing.index_by { |r| rule_signature(r.attributes.symbolize_keys) }
      desired_by_sig = rules.index_by { |r| rule_signature(r) }

      to_delete = existing_by_sig.keys - desired_by_sig.keys
      to_create = desired_by_sig.keys - existing_by_sig.keys

      server.firewall_rules.where(id: existing_by_sig.values_at(*to_delete).compact.map(&:id)).delete_all if to_delete.any?

      to_create.each do |sig|
        attrs = desired_by_sig.fetch(sig)
        server.firewall_rules.create!(
          protocol: attrs.fetch(:protocol),
          port: attrs.fetch(:port, nil),
          port_range: attrs.fetch(:port_range, nil),
          source: attrs.fetch(:source, nil),
          action: attrs.fetch(:action),
          comment: attrs.fetch(:comment, nil)
        )
      end

      true
    end

    def rule_signature(rule)
      [
        rule.fetch(:protocol, nil),
        rule.fetch(:port, nil),
        normalize_range(rule.fetch(:port_range, nil))&.begin,
        normalize_range(rule.fetch(:port_range, nil))&.end,
        rule.fetch(:source, nil),
        rule.fetch(:action, nil)
      ].join("|")
    end

    def configure_system_firewall(server_id)
      server = ::Server.includes(:firewall_rules).find(server_id)
      rules = server.firewall_rules.to_a

      apply_rules_to_system(server, rules)
    end

    def apply_rules_to_system(server, rules)
      return if rules.empty?

      rules.each do |rule|
        apply_rule(server, rule)
      end
    end

    def apply_rule(_server, rule)
      protocol = rule.protocol.to_s.downcase
      return unless ALLOWED_PROTOCOLS.include?(protocol)

      # Intentionally left as integration point for system firewall commands.
      @logger&.info("Applying firewall rule: #{rule.id}")
    end
  end
end