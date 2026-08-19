# frozen_string_literal: true

require "digest"
require "fileutils"
require "prism"
require "timeout"
require_relative "semantic_fingerprint"

module Master
  module Review
    module Scan
      class FileProcessor
        RUBY_EXT = %w[.rb .rake .gemspec].freeze
        LOCK_DIR = ".constitutional_locks"
        LOCK_TIMEOUT = 30
        STALE_LOCK_AGE = 300
        MAX_FILE_BYTES = 10 * 1024 * 1024
        MAX_LINES = 10_000

        # Fraction of otherwise-clean files that still get the semantic pass.
        # Keyed on the path digest rather than rand, so two scans of the same
        # tree ask the same questions and their reports can be compared.
        SEMANTIC_SAMPLE = ENV.fetch("MASTER_SCAN_SEMANTIC_SAMPLE", "0.1").to_f

        def initialize(event_bus: nil)
          @bus = event_bus
        end

        def call(path:, depth:, rules:)
          with_file_lock(path) do
            code = read_file(path)
            return code if code.err?

            ast = parse_ruby(code.value!, path)
            fingerprint = Master::Review::Scan::SemanticFingerprint.for(code.value!)
            findings = apply_rules(code: code.value!, ast:, path:, rule_set: rules)
            findings = annotate_findings(findings, fingerprint:)
            publish_scan_result(path:, depth:, findings:)
            Result.ok(findings)
          end
        rescue StandardError => e
          @bus&.publish("scan:error", path:, error: e.message)
          Result.err("scan failed: #{e.message}", category: :infrastructure)
        end

        private

        def read_file(path)
          validation = validate_file(path)
          return validation if validation.err?

          code = File.read(path, encoding: "UTF-8")
          return Result.err("file too long: #{path}", category: :validation) if code.lines.count > MAX_LINES

          @bus&.publish("scan:file_read", path:, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(law_conducted(path, code))
        end

        # A law file necessarily contains the pattern it forbids — detector,
        # fix text, bad fixture. Law.conduct neutralizes those lines (keeping
        # line numbers) before law judges law/; that only covered Law.scan,
        # so every REGISTRY rule read law/ raw and NULL_BLINDNESS flagged
        # law/null_blindness.rb's own detector. One read site, so every rule
        # sees the same conducted text.
        def law_conducted(path, code)
          return code unless path.to_s.match?(%r{/law/[^/]+\.rb\z})

          require File.join(Master::ROOT, "law", "law") unless defined?(Law)
          Law.conduct(code)
        end

        def validate_file(path)
          return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)
          return Result.err("symlink not allowed: #{path}", category: :validation) if File.symlink?(path)
          return Result.err("binary file skipped: #{path}", category: :validation) if Master.binary_file?(path)
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
          return result.value if result.success?

          attempt_syntax_repair(path, code, result.errors)
        rescue StandardError => e
          @bus&.publish("scan:parse_error", path:, error: e.message)
          nil
        end

        def attempt_syntax_repair(path, code, errors)
          @bus&.publish("scan:syntax_fault", path:, error_count: errors.size)
          repair = AutonomousRepairer.heal(path:, source: code, event_bus: @bus)
          return if repair.err?

          re_parse = Prism.parse(repair.value!)
          return re_parse.value if re_parse.success?

          @bus&.publish("scan:syntax_repair_failed", path:)
          nil
        end

        def apply_rules(code:, ast:, path:, rule_set:)
          lexical, structural, semantic = partition_rules(rule_set, ast)
          findings = []
          findings.concat(run_rule_pass(pass: :lexical, rules: lexical, code:, ast:, path:))
          findings.concat(run_rule_pass(pass: :structural, rules: structural, code:, ast:, path:))
          return findings if lexical_error?(findings)
          return skip_semantic(path:, rules: semantic, findings:) unless semantic_due?(findings, path)

          findings.concat(run_rule_pass(pass: :semantic, rules: semantic, code:, ast:, path:))
        end

        # 74 of the 225 declared rules reach a file only through the semantic
        # pass, and the pass ran only when the cheap passes had already found
        # something. So a file that read as clean was never asked the 74
        # questions — and reported "0 findings", which is a claim about the whole
        # rule set rather than about the third of it that ran.
        #
        # The cost gate is real: one LLM call per file is not free on a tree this
        # size. Keeping it, but sampling a deterministic slice so clean files are
        # not permanently exempt, and saying so when a file is skipped.
        def semantic_due?(findings, path)
          return true unless findings.empty?
          return false if SEMANTIC_SAMPLE <= 0

          Digest::SHA256.hexdigest(sample_key(path))[0, 8].to_i(16) % 1000 < (SEMANTIC_SAMPLE * 1000).round
        end

        # Relative to the repo, not the absolute path: keyed on the latter, two
        # checkouts of the same tree sample different files and a scan is not
        # reproducible off the machine that ran it. Relative also holds still
        # while the file is edited, so a rule does not switch on and off under
        # someone's keystrokes.
        def sample_key(path)
          path.to_s.delete_prefix("#{Master::ROOT}/")
        end

        def skip_semantic(path:, rules:, findings:)
          @bus&.publish("scan:semantic_skipped", path:, rule_count: rules.size, reason: "clean file, outside sample")
          findings
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
          @bus&.publish("scan:pass", path:, pass:, rule_count: rules.size)
          rules.flat_map { |rule| run_rule(rule:, code:, ast:, path:) }
        end

        def semantic_rule?(rule)
          rule.is_a?(Master::Review::Scan::Rules::SemanticRule) ||
            (rule.respond_to?(:id) && rule.id.to_s == "semantic")
        end

        def annotate_findings(findings, fingerprint:)
          Array(findings).map { |finding| add_fingerprint(finding, fingerprint:) }
        end

        def add_fingerprint(finding, fingerprint:)
          meta = { fingerprint: }
          return finding.merge(meta) if finding.respond_to?(:merge)
          return finding.to_h.merge(meta) if finding.respond_to?(:to_h)

          finding
        end

        def lexical_error?(findings)
          findings.any? do |finding|
            severity = finding.respond_to?(:severity) ? finding.severity : finding[:severity]
            next false if severity.nil?

            %i[error critical].include?(severity.to_sym)
          end
        end

        def run_rule(rule:, code:, ast:, path:)
          if ast && rule.respond_to?(:check_ast)
            rule.check_ast(ast, code, path:)
          else
            rule.check(code, path:)
          end
        end

        def publish_scan_result(path:, depth:, findings:)
          @bus&.publish("scan:complete", path:, depth:, count: findings.size, top_rules: top_rules(findings))
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
