# frozen_string_literal: true

require "digest"
require "prism"

module Master
  module Judge
    module Scan
      class FileProcessor
        RUBY_EXT = %w[.rb .rake .gemspec].freeze

        def initialize(event_bus: nil)
          @bus = event_bus
        end

        def call(path:, depth:, rules:)
          code = read_file(path)
          return code if code.err?

          ast = parse_ruby(code.value!, path)
          findings = apply_rules(code: code.value!, ast: ast, path: path, rule_set: rules)
          publish_scan_result(path: path, depth: depth, findings: findings)
          Result.ok(findings)
        rescue StandardError => e
          @bus&.publish("scan:error", path: path, error: e.message)
          Result.err("scan failed: #{e.message}", category: :infrastructure)
        end

        private

        def read_file(path)
          return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

          code = File.read(path, encoding: "UTF-8")
          @bus&.publish("scan:file_read", path: path, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(code)
        end

        def parse_ruby(code, path)
          return unless RUBY_EXT.include?(File.extname(path))

          result = Prism.parse(code)
          result.success? ? result.value : nil
        rescue StandardError => e
          @bus&.publish("scan:parse_error", path: path, error: e.message)
          nil
        end

        def apply_rules(code:, ast:, path:, rule_set:)
          semantic, static = rule_set.partition { |rule| semantic_rule?(rule) }
          findings = static.flat_map { |rule| run_rule(rule: rule, code: code, ast: ast, path: path) }
          return findings if lexical_error?(findings)

          findings + semantic.flat_map { |rule| run_rule(rule: rule, code: code, ast: ast, path: path) }
        end

        def semantic_rule?(rule)
          rule.is_a?(Master::Judge::Scan::Rules::SemanticRule) ||
            (rule.respond_to?(:id) && rule.id.to_s == "semantic")
        end

        def lexical_error?(findings)
          findings.any? do |finding|
            severity = finding.respond_to?(:severity) ? finding.severity : finding[:severity]
            %i[error critical].include?(severity.to_sym)
          end
        end

        def run_rule(rule:, code:, ast:, path:)
          if ast && rule.respond_to?(:check_ast)
            rule.check_ast(ast, code, path: path)
          else
            rule.check(code, path: path)
          end
        end

        def publish_scan_result(path:, depth:, findings:)
          @bus&.publish("scan:complete", path: path, depth: depth, count: findings.size, top_rules: top_rules(findings))
        end

        def top_rules(findings, limit: 3)
          findings.each_with_object(Hash.new(0)) do |finding, counts|
            rule = finding_rule(finding)
            counts[rule] += 1 if rule
          end.sort_by { |rule, count| [-count, rule] }.first(limit).to_h
        end

        def finding_rule(finding)
          rule =
            if finding.respond_to?(:[])
              finding[:rule] || finding[:rule_id] || finding["rule"] || finding["rule_id"]
            elsif finding.respond_to?(:rule)
              finding.rule
            elsif finding.respond_to?(:rule_id)
              finding.rule_id
            end

          rule.to_s unless rule.nil? || rule.to_s.empty?
        end
      end
    end
  end
end
