# frozen_string_literal: true

require "yaml"

module Master
  module Pub4
    # Serves BootstrapDocs#section("deploy") and owns the one read
    # of the debt register: Pub4::StatusReport#backlog_open_count delegates here
    # rather than parsing the same YAML a second way, which is how one of the two
    # copies stayed broken unnoticed for as long as it did.
    module OperatorDocs
      # __dir__ is MASTER/lib/deploy, so the repo root is three levels up, not four.
      # At four this resolved to the directory *containing* the checkout, both YAML
      # paths were absent, and every method degraded to its empty default without
      # raising: open_debt_count answered 0 against a 14-item register.
      ROOT = File.expand_path("../../..", __dir__)
      OPERATOR_PATH = File.join(ROOT, "OPENBSD", "data", "operator.yml")
      DEBT_RELATIVE = File.join("OPENBSD", "data", "debt.yml")
      DEBT_PATH = File.join(ROOT, DEBT_RELATIVE)

      module_function

      def load_operator
        return {} unless File.file?(OPERATOR_PATH)

        YAML.safe_load(File.read(OPERATOR_PATH)) || {}
      end

      # root: so the cross-repo diagnostic can pass its own checkout rather than
      # inheriting this file's idea of where the repo is.
      def load_debt(root: ROOT)
        path = root == ROOT ? DEBT_PATH : File.join(root, DEBT_RELATIVE)
        return { "open" => [] } unless File.file?(path)

        YAML.safe_load(File.read(path)) || { "open" => [] }
      end

      def render_deploy
        operator = load_operator
        lines = ["OPERATOR operator (runtime: OPENBSD/data/operator.yml)", ""]
        lines << operator.dig("app_layout", "summary").to_s
        lines << "Deploy: #{operator.dig('app_layout', 'deploy_entrypoint')}"
        lines << "Deployed: #{operator.dig('app_layout', 'deployed_tree')}"
        lines << ""
        lines << "Single source of truth:"
        operator.fetch("single_source_of_truth", {}).each do |key, path|
          lines << "  #{key}: #{path}"
        end
        lines << ""
        lines << "Recipes:"
        Array(operator["recipes"]).each do |recipe|
          lines << "  #{recipe['want']}: #{recipe['run']}"
        end
        lines.join("\n")
      end

      def open_debt_count(root: ROOT)
        Array(load_debt(root:)["open"]).size
      end
    end
  end
end
