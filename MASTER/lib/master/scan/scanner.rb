# frozen_string_literal: true

module Master
  module Scan
    class Scanner
      DEPTH_RULES = {
        quick:    %w[frozen_string bare_rescue],
        standard: %w[frozen_string bare_rescue explicit immutable cqs self_explaining
                     long_method god_class duplicate_code prune srp pola
                     rubocop reek nielsen],
        hunt:     :all,
        critique: :all,
        deep:     :all
      }.freeze

      def initialize(rules: nil, event_bus: nil)
        @rules = rules || []
        @bus   = event_bus
      end

      def scan(path, depth: :standard)
        return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

        code = File.read(path)
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

      def active_rules(depth)
        allowed = DEPTH_RULES[depth]
        return @rules if allowed == :all
        @rules.select { |r| allowed.include?(r.id) }
      end
    end
  end
end
