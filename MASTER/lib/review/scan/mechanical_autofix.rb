# frozen_string_literal: true

require_relative "ast_fixer"

module Master
  module Review
    module Scan
      # Deterministic AstFixer pass shared by /scan and /self.
      # Only runs on files that have findings whose rule has auto_fix=true.
      # Idempotent; safe to re-run. Opt out with --dry-run, --no-autofix, or MASTER_SCAN_AUTOFIX=0.
      class MechanicalAutofix
        Applied = Struct.new(:path, :transforms, keyword_init: true)

        def self.enabled?(env: ENV)
          env.fetch("MASTER_SCAN_AUTOFIX", "1") != "0"
        end

        def initialize(scanner:, root:, event_bus: nil)
          @scanner = scanner
          @root = root.to_s
          @bus = event_bus
        end

        def apply(pairs)
          autofixable_paths(pairs).filter_map { |path| fix_path(path) }
        end

        private

        def fix_path(path)
          return unless File.file?(path)

          result = AstFixer.fix(path, File.read(path, encoding: "UTF-8"), event_bus: @bus)
          return unless result&.changed

          rel = relative_path(path)
          applied = Applied.new(path: rel, transforms: result.transforms)
          @bus&.publish("scan_autofix:applied", path: rel, transforms: result.transforms)
          # Back-compat event name used by SelfScan consumers/tests
          @bus&.publish("self_autofix:applied", path: rel, transforms: result.transforms)
          applied
        end

        def relative_path(path)
          prefix = "#{@root}/"
          path.to_s.start_with?(prefix) ? path.to_s.delete_prefix(prefix) : path.to_s
        end

        def autofixable_paths(pairs)
          Array(pairs).filter_map do |path, file_result|
            findings = Result.wrap(file_result).value_or([])
            path if findings.any? { |finding| autofixable_finding?(finding) }
          end.uniq
        end

        def autofixable_finding?(finding)
          rule = rules_by_id[finding_rule_id(finding).to_s]
          rule&.auto_fix
        end

        def finding_rule_id(finding)
          return finding.rule if finding.respond_to?(:rule)
          return finding[:rule] if finding.respond_to?(:[])

          nil
        end

        def rules_by_id
          @rules_by_id ||= scanner_rules.to_h { |rule| [rule.id.to_s, rule] }
        end

        def scanner_rules
          return @scanner.rules if @scanner.respond_to?(:rules)

          Array(@scanner.instance_variable_get(:@rules))
        end
      end
    end
  end
end
