# frozen_string_literal: true

require "yaml"

module Master
  module Deploy
    module OperatorDocs
      # __dir__ is MASTER/lib/deploy, so the repo root is three levels up, not four.
      # At four this resolved to the directory *containing* the checkout, both YAML
      # paths were absent, and every method degraded to its empty default without
      # raising: open_debt_count answered 0 against a 14-item register, and
      # render_deploy printed its headings over four blank values. Nothing caught it
      # because nothing calls this module (see operator_docs_module_is_unreferenced).
      ROOT = File.expand_path("../../..", __dir__)
      OPERATOR_PATH = File.join(ROOT, "OPENBSD", "data", "operator.yml")
      DEBT_PATH = File.join(ROOT, "OPENBSD", "data", "debt.yml")

      module_function

      def load_operator
        return {} unless File.file?(OPERATOR_PATH)

        YAML.safe_load(File.read(OPERATOR_PATH)) || {}
      end

      def load_debt
        return { "open" => [] } unless File.file?(DEBT_PATH)

        YAML.safe_load(File.read(DEBT_PATH)) || { "open" => [] }
      end

      def render_deploy
        data = load_operator
        lines = ["OPERATOR operator (runtime: OPENBSD/data/operator.yml)", ""]
        lines << data.dig("app_layout", "summary").to_s
        lines << "Deploy: #{data.dig('app_layout', 'deploy_entrypoint')}"
        lines << "Deployed: #{data.dig('app_layout', 'deployed_tree')}"
        lines << ""
        lines << "Single source of truth:"
        data.fetch("single_source_of_truth", {}).each do |key, path|
          lines << "  #{key}: #{path}"
        end
        lines << ""
        lines << "Recipes:"
        Array(data["recipes"]).each do |recipe|
          lines << "  #{recipe['want']}: #{recipe['run']}"
        end
        lines.join("\n")
      end

      def open_debt_count
        Array(load_debt["open"]).size
      end
    end
  end
end
