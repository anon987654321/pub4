# frozen_string_literal: true

require "yaml"

module Master
  module Pub4
    # Serves BootstrapDocs#section("deploy") and owns the one read of the open
    # operator debt: Pub4::StatusReport#backlog_open_count delegates here rather
    # than counting a second way, which is how one of the two copies of the old
    # register stayed broken unnoticed for as long as it did.
    #
    # The per-tree backlog files were consolidated into the repo-root TODO.md.
    # Open operator debt now lives under its OPENBSD section, one item per hidden
    # "<!-- open-debt -->" marker line; this counts those.
    module OperatorDocs
      # __dir__ is MASTER/lib/pub4, so the repo root is three levels up, not four.
      # At four this resolved to the directory *containing* the checkout, the path
      # was absent, and every method degraded to its empty default without raising.
      ROOT = File.expand_path("../../..", __dir__)
      OPERATOR_PATH = File.join(ROOT, "OPENBSD", "data", "operator.yml")
      DEBT_RELATIVE = "TODO.md"
      DEBT_PATH = File.join(ROOT, DEBT_RELATIVE)
      OPEN_DEBT_MARKER = "<!-- open-debt -->"

      module_function

      def load_operator
        return {} unless File.file?(OPERATOR_PATH)

        YAML.safe_load(File.read(OPERATOR_PATH)) || {}
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

      # root: so the cross-repo diagnostic can pass its own checkout rather than
      # inheriting this file's idea of where the repo is. Counts marker lines,
      # not substrings, so prose that names the marker cannot inflate the number.
      def open_debt_count(root: ROOT)
        path = root == ROOT ? DEBT_PATH : File.join(root, DEBT_RELATIVE)
        return 0 unless File.file?(path)

        File.readlines(path).count { |line| line.strip == OPEN_DEBT_MARKER }
      end
    end
  end
end
