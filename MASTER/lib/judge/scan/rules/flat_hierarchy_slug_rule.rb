# frozen_string_literal: true

module Master
  module Judge
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
