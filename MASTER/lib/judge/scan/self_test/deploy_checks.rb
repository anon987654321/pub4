# frozen_string_literal: true

module Master
  module Judge
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
            rescue StandardError
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
