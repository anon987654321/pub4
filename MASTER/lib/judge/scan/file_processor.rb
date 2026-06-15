# frozen_string_literal: true

require "digest"

module Master
  module Judge
    module Scan
      # O109: extracted file read → parse → apply → publish pipeline from Scanner#scan.
      class FileProcessor
        RUBY_EXT = %w[.rb .rake .gemspec].freeze

        def initialize(event_bus: nil, rules: [])
          @bus = event_bus
          @rules = Array(rules)
        end

        def process(path, code:, ast:, rule_set:)
          findings = apply_rules(code, ast, path, rule_set)
          publish_scan_result(path, findings)
          findings
        end

        def read_file(path)
          code = File.read(path, encoding: "UTF-8")
          @bus&.publish("scan:file_read", path:, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(code)
        end

        def parse_ruby(code, path)
          return unless RUBY_EXT.include?(File.extname(path))

          result = Prism.parse(code)
          result.success? ? result.value : nil
        rescue StandardError => e
          @bus&.publish("scan:parse_error", path:, error: e.message)
          nil
        end

        private

        def apply_rules(code, ast, path, rule_set)
          fast_rules, semantic_rules = partition_rules(rule_set)
          findings = fast_rules.flat_map { |rule| run_rule(rule:, code:, ast:, path:) }
          return findings if semantic_rules.empty? || findings.empty?

          findings + semantic_rules.flat_map { |rule| run_rule(rule:, code:, ast:, path:) }
        end

        def partition_rules(rule_set)
          semantic = []
          fast = rule_set.reject do |rule|
            name = rule.class.name&.split("::")&.last
            next false unless name == "SemanticRule"
            semantic << rule
            true
          end
          [fast, semantic]
        end

        def run_rule(rule:, code:, ast:, path:)
          rule.scan(code, ast, path)
        rescue StandardError => e
          @bus&.publish("scan:rule_error", rule: rule.id, path:, error: e.message)
          []
        end

        def publish_scan_result(path, findings)
          @bus&.publish("scan:complete", path:, violations: findings.size)
        end
      end
    end
  end
end