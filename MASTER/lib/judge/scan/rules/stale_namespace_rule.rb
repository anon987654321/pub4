# frozen_string_literal: true

module Master
  module Judge
    module Scan
      stale_config = Master.load_yaml(Master.data_path("stale_namespaces.yml"))
      stale_constants = Array(stale_config["stale_constants"]).filter_map { |row| row["old"] if row.is_a?(Hash) }
      stale_pattern = Regexp.union(stale_constants.map { |name| /\b#{Regexp.escape(name)}\b/ })

      RuleDSL.rule :STALE_NAMESPACE,
        severity: :error,
        tags: %i[ONE_SOURCE],
        applies_to: %i[ruby],
        description: "retired constants must not return" do |source, path:|
          next [] if stale_constants.empty? || path.end_with?("stale_namespace_rule.rb")

          scan_lines(source, stale_pattern, message: "retired constant — use data/stale_namespaces.yml replacement")
        end
    end
  end
end
