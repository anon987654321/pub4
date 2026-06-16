# frozen_string_literal: true

require "digest"
require "fileutils"
require "prism"
require "timeout"

module Master
  module Judge
    module Scan
      class FileProcessor
        RUBY_EXT = %w[.rb .rake .gemspec].freeze
        LOCK_DIR = ".constitutional_locks"
        LOCK_TIMEOUT = 30
        STALE_LOCK_AGE = 300
        MAX_FILE_BYTES = 10 * 1024 * 1024
        MAX_LINES = 10_000

        def initialize(event_bus: nil)
          @bus = event_bus
        end

        def call(path:, depth:, rules:)
          with_file_lock(path) do
            code = read_file(path)
            return code if code.err?

            ast = parse_ruby(code.value!, path)
            fingerprint = semantic_fingerprint(code.value!, ast)
            findings = apply_rules(code: code.value!, ast: ast, path: path, rule_set: rules)
            findings = annotate_findings(findings, fingerprint: fingerprint, ast: ast)
            publish_scan_result(path: path, depth: depth, findings: findings)
            Result.ok(findings)
          end
        rescue StandardError => e
          @bus&.publish("scan:error", path: path, error: e.message)
          Result.err("scan failed: #{e.message}", category: :infrastructure)
        end

        private

        def read_file(path)
          validation = validate_file(path)
          return validation if validation.err?

          code = File.read(path, encoding: "UTF-8")
          return Result.err("file too long: #{path}", category: :validation) if code.lines.count > MAX_LINES

          @bus&.publish("scan:file_read", path: path, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(code)
        end

        def validate_file(path)
          return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)
          return Result.err("symlink not allowed: #{path}", category: :validation) if File.symlink?(path)
          return Result.err("binary file skipped: #{path}", category: :validation) if File.binary?(path)
          return Result.err("file too large: #{path}", category: :validation) if File.size(path) > MAX_FILE_BYTES

          Result.ok(path)
        rescue StandardError => e
          Result.err("file validation failed: #{e.message}", category: :validation)
        end

        def with_file_lock(path)
          lock_path = lock_path_for(path)
          FileUtils.mkdir_p(File.dirname(lock_path))
          deadline = Time.now + LOCK_TIMEOUT
          loop do
            remove_stale_lock(lock_path)
            begin
              File.open(lock_path, File::WRONLY | File::CREAT | File::EXCL) { |file| file.write("#{Process.pid}\n") }
              break
            rescue Errno::EEXIST
              raise "lock timeout for #{path}" if Time.now >= deadline
              sleep 0.05
            end
          end
          yield
        ensure
          File.delete(lock_path) if lock_path && File.exist?(lock_path)
        end

        def remove_stale_lock(lock_path)
          return unless File.exist?(lock_path)
          return unless Time.now - File.mtime(lock_path) > STALE_LOCK_AGE

          File.delete(lock_path)
          @bus&.publish("scan:stale_lock_removed", path: lock_path)
        rescue StandardError => e
          @bus&.publish("scan:lock_error", path: lock_path, error: e.message)
        end

        def lock_path_for(path)
          digest = Digest::SHA256.hexdigest(File.expand_path(path))
          File.join(Master::ROOT, LOCK_DIR, "#{digest}.lock")
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
          lexical, structural, semantic = partition_rules(rule_set, ast)
          findings = []
          findings.concat(run_rule_pass(pass: :lexical, rules: lexical, code: code, ast: ast, path: path))
          findings.concat(run_rule_pass(pass: :structural, rules: structural, code: code, ast: ast, path: path))
          return findings if findings.empty? || lexical_error?(findings)

          findings.concat(run_rule_pass(pass: :semantic, rules: semantic, code: code, ast: ast, path: path))
        end

        def partition_rules(rule_set, ast)
          semantic = []
          structural = []
          lexical = []
          rule_set.each do |rule|
            if semantic_rule?(rule)
              semantic << rule
            elsif ast && rule.respond_to?(:check_ast)
              structural << rule
            else
              lexical << rule
            end
          end
          [lexical, structural, semantic]
        end

        def run_rule_pass(pass:, rules:, code:, ast:, path:)
          @bus&.publish("scan:pass", path: path, pass: pass, rule_count: rules.size)
          rules.flat_map { |rule| run_rule(rule: rule, code: code, ast: ast, path: path) }
        end

        def semantic_rule?(rule)
          rule.is_a?(Master::Judge::Scan::Rules::SemanticRule) ||
            (rule.respond_to?(:id) && rule.id.to_s == "semantic")
        end

        def annotate_findings(findings, fingerprint:, ast:)
          Array(findings).map do |finding|
            add_fingerprint(finding, fingerprint: fingerprint, ast: ast)
          end
        end

        def add_fingerprint(finding, fingerprint:, ast:)
          meta = { fingerprint: fingerprint }
          return finding.merge(meta) if finding.respond_to?(:merge)
          return finding.to_h.merge(meta) if finding.respond_to?(:to_h)

          finding
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

        def semantic_fingerprint(code, ast)
          counts = {
            line_count: code.lines.count,
            class_count: code.scan(/^\s*class\s+/).size,
            method_count: code.scan(/^\s*def\s+/).size,
            def_names: code.scan(/^\s*def\s+([a-zA-Z_][\w!?=]*)/).flatten.sort,
            constant_names: code.scan(/\b([A-Z][A-Z0-9_]*(?:::[A-Z][A-Z0-9_]*)*)\b/).flatten.sort,
            ast_present: !ast.nil?
          }
          Digest::SHA256.hexdigest(Marshal.dump(counts))
        rescue StandardError
          Digest::SHA256.hexdigest(code.to_s)
        end
      end
    end
  end
end
