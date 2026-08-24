# frozen_string_literal: true

require_relative "rule_dsl"


# ---- merged from lib/review/scan/self_test/deploy_checks.rb (one-file directory collapse, 2026-08-19) ----
module Master
  module Review
    module Scan
      class SelfTest
        # Self-test checks run against the OPENBSD-mirrored deploy tree
        # (rails/, openbsd/, sh/, postpro/) — a separate corpus from MASTER's
        # own lib/, so kept as its own concern with its own path resolution.
        module DeployChecks
          private

          def deploy_bare_rescue_findings
            deploy_paths.flat_map do |path|
              next [] unless path.end_with?(".rb", ".sh")
              read_lines(path).each_with_index.filter_map do |line, index|
                next unless line.match?(/^\s*rescue\s*(?:$|=>)/) || line.match?(/^\s*trap\s+.*\s+do/)
                finding(path:, line: index + 1, message: "bare rescue/trap in OPERATOR — use explicit error handling")
              end
            end
          end

          def deploy_duplicate_id_findings
            deploy_paths.select { |p| p.end_with?(".yml") }.flat_map do |path|
              yaml = Master.load_yaml(path)
              ids = rule_ids(yaml)
              ids.group_by(&:itself).filter_map do |id, values|
                finding(path:, line: 1, message: "duplicate id #{id} in OPERATOR config") if values.size > 1
              end
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "SelfTest.operator_duplicates", severity: :load_bearing)
              []
            end
          end

          def deploy_nesting_findings
            deploy_paths.flat_map do |path|
              next [] unless path.end_with?(".sh", ".erb")
              lines = read_lines(path)
              depth = 0
              findings = []
              lines.each_with_index do |line, i|
                depth += 1 if line.match?(/^\s*(if|do|case|while|for)\b/)
                depth -= 1 if line.match?(/^\s*(fi|done|esac|end)\b/)
                findings << finding(path:, line: i + 1, message: "nesting >4 in OPERATOR (violates LINEARITY)") if depth > 4
              end
              findings
            end
          end

          def deploy_god_class_findings
            deploy_paths.select { |p| p.end_with?(".rb") }.flat_map do |path|
              code = read_text(path) rescue ""
              code.scan(/^\s*def\s+\w+/).size > 10 ? [finding(path:, line: 1, message: "potential god class in OPERATOR rails (>10 defs)")] : []
            end
          end

          def deploy_small_files_findings
            deploy_paths.select { |p| File.size(p) > 300 * 80 rescue false }.map do |path|
              finding(path:, line: 1, message: "OPERATOR file >~300 lines (violates DENSITY/SMALL_FILES)")
            end
          end

          def deploy_paths
            @deploy_paths ||= build_deploy_paths
          end

          def build_deploy_paths
            deploy_root = File.expand_path("../OPENBSD", @root)
            return [] unless File.directory?(deploy_root)

            patterns = [
              File.join(deploy_root, "rails", "**", "*.rb"),
              File.join(deploy_root, "openbsd", "**", "*"),
              File.join(deploy_root, "sh", "**", "*"),
              File.join(deploy_root, "postpro", "**", "*.rb"),
              File.join(deploy_root, "*.rb"),
            ]
            patterns.flat_map { |pattern| Dir.glob(pattern) }
                    .select { |path| File.file?(path) }
                    .select { |path| deploy_path_allowed?(path, deploy_root) }
                    .uniq.sort
          end

          def deploy_path_allowed?(path, deploy_root)
            rel = path.delete_prefix("#{deploy_root}/")
            !Scanner.skip_path?(rel) && !rel.split("/").include?("db")
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      class SelfTest
        include DeployChecks

        Check = Data.define(:law, :description, :findings) do
          def ok? = findings.empty?
        end

        Summary = Data.define(:checks) do
          def violation_count = checks.sum { |check| check.findings.size }
          def ok? = violation_count.zero?
          def line = "self-test: #{violation_count} violations"
          def to_h = checks.to_h { |check| [check.law, { ok: check.ok?, findings: check.findings }] }
        end

        def initialize(root:, event_bus: nil)
          @root = root
          @bus = event_bus
          rules = Master.load_yaml(File.join(root, "data", "rules.yml")) || {}
          @checks = rules.dig("self_test", "laws_apply_to_self") || {}
        end

        def call(laws: nil)
          summary = Summary.new(checks: build_checks(laws:))
          @bus&.publish("self_test:complete", violations: summary.violation_count, checks: summary.to_h)
          @bus&.publish("self_violation", violations: summary.violation_count, checks: summary.to_h) unless summary.ok?
          Result.ok(summary)
        rescue StandardError => e
          @bus&.publish("self_test:error", error: e.message)
          Result.err("self-test failed: #{e.message}", category: :infrastructure)
        end

        private

        def read_lines(path)
          File.readlines(path, chomp: true, encoding: "UTF-8", invalid: :replace, undef: :replace)
        end

        def read_text(path)
          File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
        end

        def build_checks(laws: nil)
          selected_laws = laws&.to_set
          law_checks.filter_map do |law, body|
            next if selected_laws && !selected_laws.include?(law)
            check(law, &body)
          end
        end

        def law_checks
          [
            ["ROBUSTNESS", lambda {
              bare_rescue_findings + deploy_bare_rescue_findings + timeout_findings +
                js_silent_catch_findings + library_verify_findings
            }],
            ["SINGULARITY", lambda { duplicate_rule_id_findings + cross_yaml_duplicate_key_findings + deploy_duplicate_id_findings }],
            ["LINEARITY", lambda { structural_findings(Rules::NestingDepthRule.new) + deploy_nesting_findings }],
            ["PROXIMITY", lambda { rule_test_proximity_findings }],
            ["ABSTRACTION", lambda { structural_findings(Rules::GodClassRule.new) + deploy_god_class_findings }],
            ["DENSITY", lambda { structural_findings(Rules::SmallFunctionsRule.new) + deploy_small_files_findings + face_pool_findings }],
            ["KERNEL_ADHERENCE", lambda { kernel_wiring_findings }],
            ["PRINCIPLE_MAP", lambda { principle_map_findings }],
          ]
        end

        def check(law)
          Check.new(law:, description: @checks[law].to_s, findings: yield)
        end

        def ruby_lib_paths
          Dir.glob(File.join(@root, "lib", "**", "*.rb")).sort
        end

        def bare_rescue_findings
          ruby_lib_paths.flat_map do |path|
            read_lines(path).each_with_index.filter_map do |line, index|
              next unless line.match?(/^\s*rescue\s*(?:$|=>)/)
              finding(path:, line: index + 1, message: "bare rescue — use rescue StandardError")
            end
          end
        end

        def timeout_findings
          targets = ruby_lib_paths.select { |p| p.include?("/io/") || p.include?("/review/llm") || p.include?("/core/") }
          targets.flat_map do |path|
            # Strip full-line comments first -- a file that only *mentions*
            # Open3/Net::HTTP in prose (e.g. explaining a caller's behavior)
            # is not itself making an unbounded call.
            code = read_text(path).lines.reject { |line| line.match?(/\A\s*#/) }.join
            next [] unless code.match?(/\b(?:Open3\.|Net::HTTP)\b/)
            # wait_thr.join(timeout_s) is a legitimate bounded-wait idiom (join
            # returns nil on timeout without raising, so the code must check it
            # and kill the process) -- same guarantee as Timeout.timeout, just
            # spelled differently. Matched narrowly so plain Array#join(", ")
            # elsewhere in the file can't produce a false "it's bounded".
            next [] if code.match?(/Timeout\.|read_timeout|open_timeout|block_until_ms|\b\w*thr\w*\.join\(/i)
            [finding(path:, line: 1, message: "HTTP/Open3 without bounded timeout (ROBUSTNESS)")]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "SelfTest.timeout_scan", severity: :load_bearing)
            []
          end
        end

        def js_silent_catch_findings
          web = File.join(@root, "web", "public")
          return [] unless File.directory?(web)
          Dir.glob(File.join(web, "**", "*.js"))
            .reject { |path| Scanner.skip_path?(path, root: @root) }
            .flat_map do |path|
              read_lines(path).each_with_index.filter_map do |line, index|
                next unless line.match?(/catch\s*\([^)]*\)\s*\{\s*\}/)
                finding(path:, line: index + 1, message: "silent catch {} in web JS — fail visibly")
              end
            end
        end

        def duplicate_rule_id_findings
          path = File.join(@root, "data", "rules.yml")
          ids = rule_ids(Master.load_rules(root: @root))
          ids.group_by(&:itself).filter_map do |id, values|
            finding(path:, line: 1, message: "duplicate rule id #{id}") if values.size > 1
          end
        end

        def cross_yaml_duplicate_key_findings
          data_dir = File.join(@root, "data")
          top_keys = Hash.new { |h, k| h[k] = [] }
          singularity_yaml_paths(data_dir).each do |path|
            top_level_yaml_keys(path).each { |key| top_keys[key] << path }
          end
          top_keys.flat_map do |key, paths|
            next [] if paths.size < 2
            paths.drop(1).map do |path|
              finding(path:, line: 1, message: "top-level key #{key} also defined in #{paths.first} (SINGULARITY)")
            end
          end
        end

        # Registers whose top-level keys are the SUBJECT of a finding rather than
        # a configuration namespace. doc_baselines.yml#doc_paths lists dead path
        # references per document and doc_baselines.yml#doc_numbers lists untraceable
        # numbers per document, so any document carrying both debts appears in
        # both — as RAILS/FINAL_TODO.md now does. That is two registers agreeing
        # about which file has problems, not two sources of truth for one value,
        # which is what SINGULARITY exists to catch. Exempted by file rather than
        # by key: the keys are arbitrary document paths, so a key-name allowlist
        # would need a new entry every time a document acquires a second kind of
        # debt.
        SINGULARITY_EXEMPT_REGISTERS = %w[
          doc_baselines.yml
        ].freeze

        def singularity_yaml_paths(data_dir)
          Dir.glob(File.join(data_dir, "**", "*.yml")).sort.reject do |path|
            rel = path.delete_prefix("#{data_dir}/")
            # lessons/ is the one data/ subdirectory left — every other prefix
            # here named a directory that no longer existed (agents/, rules/,
            # ops/, prompts/, …), each an exemption outliving its subject.
            rel.start_with?("lessons/") ||
              SINGULARITY_EXEMPT_REGISTERS.include?(rel)
          end
        end

        def top_level_yaml_keys(path)
          document = Psych.parse_file(path)
          return [] unless document
          root = document.root
          return [] unless root.is_a?(Psych::Nodes::Mapping)

          root.children.each_slice(2).filter_map do |key_node, _value_node|
            next unless key_node.respond_to?(:value)
            key = key_node.value.to_s
            next if %w[schema meta version].include?(key)
            next if duplicate_top_level_key_allowed?(path, key)
            key
          end
        rescue Psych::Exception
          []
        end

        def duplicate_top_level_key_allowed?(path, key)
          relative = path.delete_prefix("#{File.join(@root, "data")}/")
          {
            "defaults" => %w[mcp_servers.yml models.yml],
            "openrouter" => %w[models.yml providers.yml],
            "thresholds" => %w[load.yml rules.yml],
            "voice" => %w[soul.yml voice.yml],
          }.fetch(key, []).include?(relative)
        end

        def rule_ids(value, ids = [])
          case value
          when Hash
            ids << value["id"].to_s if value.key?("id")
            value.each_value { |child| rule_ids(child, ids) }
          when Array
            value.each { |child| rule_ids(child, ids) }
          end
          ids.reject(&:empty?)
        end

        def structural_findings(rule)
          ruby_lib_paths.flat_map do |path|
            code = read_text(path)
            rule.check(code, path:).map { |result| finding(path:, line: result.line, message: result.message) }
          end
        end

        def rule_test_proximity_findings
          Dir.glob(File.join(@root, "lib", "review", "scan", "rules", "*_rule.rb")).sort.filter_map do |path|
            base = File.basename(path, ".rb")
            test_path = File.join(@root, "test", "test_#{base}.rb")
            next if File.exist?(test_path)
            finding(path:, line: 1, message: "missing nearby test #{File.basename(test_path)}")
          end
        end

        def face_pool_findings
          semantics = File.join(@root, "web", "public", "face_semantics.js")
          return [] unless File.file?(semantics)
          body = read_text(semantics)
          return [] unless body.match?(/mouthPool\.cells|eyePool\.cells/)
          [finding(path: semantics, line: 1, message: "face_semantics still mutates mouthPool/eyePool — use MASTER_FACE_BLEND")]
        end

        def library_verify_findings
          verify = Ground::LibraryVerify.new(root: @root)
          lock = File.join(@root, "Gemfile.lock")
          return [] unless File.file?(lock)

          %w[zeitwerk psych yaml].filter_map do |gem|
            result = verify.verify_gem!(gem)
            next if result.ok?

            finding(path: lock, line: 1, message: result.message.to_s)
          end
        end

        def kernel_wiring_findings
          return [] unless @root == Master::ROOT

          findings = []
          infra = File.join(@root, "lib", "review", "scan", "infra_helpers.rb")
          unless File.file?(infra)
            findings << finding(path: infra, line: 1, message: "missing infra_helpers.rb wiring layer")
          end
          audit = RuleRegistryAudit.new(root: @root).call
          if audit.adherence_pct < 35.0
            findings << finding(
              path: File.join(@root, "data", "rules.yml"), line: 1,
              message: "rule adherence #{audit.adherence_pct}% below 35% — wire lexical/structural adapters"
            )
          end
          findings
        end

        def principle_map_findings
          path = File.join(@root, "data", "principle_map.yml")
          return [finding(path:, line: 1, message: "missing data/principle_map.yml")] unless File.file?(path)

          map = Master::Ground::Map::Principle.load(root: @root)
          registered = Master::Review::Scan::Rule.registry.filter_map do |klass|
            Master::Review::Scan::RuleFactory.registry_id(klass, root: @root)&.upcase
          end
          # A rule declared in rules.yml with no Ruby class is still a rule — 126
          # of the 227 are semantic-only. Checking a principle's rule_ids against
          # the registry alone calls those unknown and reads as a broken map.
          declared = Master.flatten_rules(Master.load_rules(root: @root).fetch("rules", {}))
                           .map { |rule| rule["id"].to_s.upcase }
          map.integrity(registered_rule_ids: registered | declared).map do |msg|
            finding(path:, line: 1, message: msg)
          end
        rescue StandardError => e
          [finding(path:, line: 1, message: "principle_map integrity failed: #{e.class}: #{e.message}")]
        end

        def finding(path:, line:, message:)
          { path:, line:, message: }
        end
      end
    end
  end
end
