# frozen_string_literal: true

module Master
  module Review
    module Scan
      stale_config = (Master.load_yaml(Master.data_path("rules.yml")) || {})["stale_namespaces"] || {}
      stale_constants = Array(stale_config["stale_constants"]).filter_map { |row| row["old"] if row.is_a?(Hash) }
      # A retired name counts only as a whole constant path. `\b` sits between a
      # letter and a colon, so /\bMaster::CLI\b/ matched inside every legitimate
      # Master::CLI::* reference — 25 of selfcheck's 71 findings, all false.
      stale_pattern = Regexp.union(
        stale_constants.map { |name| /(?<![\w:])#{Regexp.escape(name)}(?!::|\w)/ }
      )

      RuleDSL.rule :STALE_NAMESPACE,
        severity: :error,
        tags: %i[ONE_SOURCE],
        applies_to: %i[ruby],
        description: "retired constants must not return" do |source, path:|
          # This file names the retired constants, so it flags itself. The old
          # exemption named stale_namespace_rule.rb, which no longer exists.
          next [] if stale_constants.empty? || path.end_with?("naming_rules.rb")

          scan_lines(source, stale_pattern, message: "retired constant — use data/rules.yml#stale_namespaces replacement")
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
          # A migration's filename is its schema_migrations key, and Rails finds
          # application_* by name. Neither can be renamed on naming-density
          # grounds, and 58 of brgen's 71 findings were migrations.
          next [] if rel.match?(%r{/(test|spec|node_modules|db/migrate)/|/application_\w+\.rb\z})

          Master::Ground::ParameterizedSlug.path_issues(rel).map do |issue|
            target = issue.to == issue.from ? issue.to : "#{File.dirname(rel)}/#{issue.to}.rb".gsub(%r{\./}, "")
            message = case issue.action
                      when "merge" then "Flat Hierarchy — #{issue.reason} (#{target})"
                      else "Flat Hierarchy — #{issue.reason}#{" → #{target}" if issue.to != issue.from}"
                      end
            finding(line: 1, message:)
          end
        end
      end
    end
  end
end
