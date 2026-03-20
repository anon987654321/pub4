# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    class Scanner
      DEPTHS_PATH = File.join(Master::ROOT, "data", "scan_depths.yml").freeze

      def initialize(rules: nil, event_bus: nil)
        @rules = rules || []
        @bus   = event_bus
      end

      def scan(path, depth: :standard)
        return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

        code = File.read(path, encoding: "UTF-8")
        active = active_rules(depth)
        findings = active.flat_map { |rule| rule.check(code, path:) }

        @bus&.publish("scan:complete", path:, depth:, count: findings.size)
        Result.ok(findings)
      rescue StandardError => e
        @bus&.publish("scan:error", path:, error: e.message)
        Result.err("scan failed: #{e.message}", category: :unknown)
      end

      def scan_dir(dir, depth: :standard, glob: "**/*.rb")
        paths   = Dir.glob(File.join(dir, glob))
        results = paths.map { |p| [p, scan(p, depth:)] }
        Result.ok(results)
      end

      def add_rule(rule)
        @rules << rule
        self
      end

      def set_agent(agent)
        @rules.each { |r| r.set_agent(agent) if r.respond_to?(:set_agent) }
        self
      end

      private

      def depth_rules
        @depth_rules ||= YAML.safe_load_file(DEPTHS_PATH)
      end

      def active_rules(depth)
        allowed = depth_rules[depth.to_s]
        return @rules if allowed == ["all"] || allowed == :all
        @rules.select { |r| allowed&.include?(r.id) }
      end
    end
  end
end
