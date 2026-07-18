# frozen_string_literal: true

module Master
  module Review
    module Scan
      stale_config = (Master.load_yaml(Master.data_path("patterns.yml")) || {})["stale_namespaces"] || {}
      stale_constants = Array(stale_config["stale_constants"]).filter_map { |row| row["old"] if row.is_a?(Hash) }
      stale_pattern = Regexp.union(stale_constants.map { |name| /\b#{Regexp.escape(name)}\b/ })

      RuleDSL.rule :STALE_NAMESPACE,
        severity: :error,
        tags: %i[ONE_SOURCE],
        applies_to: %i[ruby],
        description: "retired constants must not return" do |source, path:|
          next [] if stale_constants.empty? || path.end_with?("stale_namespace_rule.rb")

          scan_lines(source, stale_pattern, message: "retired constant — use data/patterns.yml#stale_namespaces replacement")
        end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
        RuleDSL.rule :PARAMETERIZED_SLUG,
          severity: :warning,
          tags: %i[FLAT_HIERARCHY DRY],
          applies_to: %i[ruby],
          autofix: false,
          description: "path is dense Rails-parameterize slug — Strunk-clean snake_case" do |_src, path:|
          rel = path.to_s
          next [] if rel.include?("/test/") || rel.include?("/spec/") || rel.include?("/node_modules/")

          Master::Ground::ParameterizedSlug.path_issues(rel).map do |issue|
            target = issue.to == issue.from ? issue.to : "#{File.dirname(rel)}/#{issue.to}.rb".gsub(%r{\./}, "")
            message = case issue.action
                      when "merge" then "Flat Hierarchy — #{issue.reason} (#{target})"
                      else "Flat Hierarchy — #{issue.reason}#{" → #{target}" if issue.to != issue.from}"
                      end
            finding(line: 1, message: message)
          end
        end
      end
    end
  end
end
