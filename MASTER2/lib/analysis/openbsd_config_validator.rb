# frozen_string_literal: true

require "json"

module Analysis
  class OpenbsdConfigValidator
    REQUIRED_CONFIG_KEYS = %w[hostname interfaces pf_rules].freeze

    def initialize(scope:, logger: nil)
      @scope = scope
      @logger = logger
    end

    def call
      hosts = load_hosts
      return [] if hosts.empty?

      configs_by_host_id = load_configs_by_host_id(host_ids: hosts.map(&:id))

      errors = []
      errors.concat(missing_config_errors(hosts: hosts, configs_by_host_id: configs_by_host_id))
      errors.concat(invalid_payload_errors(configs_by_host_id: configs_by_host_id))
      errors.concat(duplicate_pf_rule_errors(configs_by_host_id: configs_by_host_id))
      errors
    end

    private

    attr_reader :scope, :logger

    def load_hosts
      scope.includes(:openbsd_config).to_a
    end

    def load_configs_by_host_id(host_ids:)
      OpenbsdConfig.where(host_id: host_ids).pluck(:host_id, :payload).to_h
    end

    def missing_config_errors(hosts:, configs_by_host_id:)
      missing = hosts.reject { |h| configs_by_host_id.key?(h.id) }

      missing.map do |host|
        { host_id: host.id, error: "missing_openbsd_config" }
      end
    end

    def invalid_payload_errors(configs_by_host_id:)
      configs_by_host_id.each_with_object([]) do |(host_id, payload), errors|
        next if payload.present?

        errors << { host_id: host_id, error: "empty_payload" }
      end
    end

    def duplicate_pf_rule_errors(configs_by_host_id:)
      configs_by_host_id.each_with_object([]) do |(host_id, payload), errors|
        next if payload.blank?

        parsed = parse_payload(payload)
        next if parsed.nil?

        missing_keys = REQUIRED_CONFIG_KEYS - parsed.keys
        unless missing_keys.empty?
          errors << { host_id: host_id, error: "missing_required_keys", details: missing_keys.sort }
          next
        end

        rules = Array(parsed["pf_rules"]).map(&:to_s)
        dups = rules.group_by(&:itself).select { |_k, v| v.size > 1 }.keys
        next if dups.empty?

        errors << { host_id: host_id, error: "duplicate_pf_rules", details: dups.sort }
      end
    end

    def parse_payload(payload)
      JSON.parse(payload)
    rescue JSON::ParserError => e
      logger&.warn("OpenbsdConfigValidator: invalid JSON payload: #{e.message}")
      nil
    end
  end
end