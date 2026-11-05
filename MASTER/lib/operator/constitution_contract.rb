# frozen_string_literal: true

require "yaml"

module Operator
  class ConstitutionContract
    ROOT = File.expand_path("../../..", __dir__)
    REQUIRED = %w[
      MASTER/data/soul.yml
      MASTER/data/laws.yml
      MASTER/lib/soul.rb
      MASTER/data/project_context.yml
      MASTER/bin/master
      MASTER/lib/review/scan
      MASTER/law/definition.rb
      RAILS/CLAUDE.md
      RAILS/__shared/design_tokens.yml
      OPENBSD/CLAUDE.md
      OPENBSD/PATH_OWNERSHIP.yml
      OPENBSD/data/operator.yml
    ].freeze

    Result = Data.define(:issues) do
      def clean? = issues.empty?
    end

    def initialize(root: ROOT)
      @root = root
    end

    def check
      issues = required_paths
      require File.join(@root, "MASTER", "lib", "master") unless defined?(Master::ROOT)
      soul = load_yaml("MASTER/data/soul.yml")
      laws = load_yaml("MASTER/data/laws.yml")
      issues << "soul: golden Law reference missing or changed" unless soul.dig("references", "golden_law") == "PRESERVE_FIRST"
      issues << "soul: no canonical sacred paths declared" unless Master::Soul.sacred_paths(root: File.join(@root, "MASTER")).any?
      begin
        Master::Soul.load!(root: File.join(@root, "MASTER"))
      rescue StandardError => e
        issues << "soul: canonical Ruby identity failed integrity verification (#{e.class})"
      end
      tokens = load_yaml("MASTER/data/tokens.yml")
      issues << "rules: missing design tokens" unless tokens["tokens"].is_a?(Hash)
      begin
        Master::FlatLawCatalogue.validate!(laws)
        nodes = Master::FlatLawCatalogue.entries(laws).select { |entry| entry["node"] }
        issues << "laws: expected nine ordered invariant nodes" unless nodes.size == 9
      rescue StandardError => e
        issues << "laws: canonical constitution failed validation (#{e.class}: #{e.message})"
      end
      # The typographic Laws credit their source in the Law file that defines them.
      laws = Dir.glob(File.join(@root, "MASTER", "law", "*.rb"))
      issues << "rules: no Bringhurst reference" unless laws.any? { |file| File.read(file).include?("Bringhurst") }
      issues.concat(law_issues)
      issues.concat(law_catalogue_issues)
      issues.concat(tree_authority_issues)
      Result.new(issues.uniq.freeze)
    rescue StandardError => e
      Result.new((issues + ["constitution: #{e.class}: #{e.message}"]).uniq.freeze)
    end

    private

    def required_paths
      REQUIRED.filter_map do |relative|
        relative unless File.exist?(File.join(@root, relative))
      end
    end

    def load_yaml(relative)
      YAML.safe_load_file(File.join(@root, relative), aliases: true) || {}
    end

    def law_issues
      require File.join(@root, "MASTER", "law", "definition")
      ::Law.load_all(File.join(@root, "MASTER", "law")) if ::Law.definitions.empty?
      ::Law.definitions.empty? ? ["law: no executable laws loaded"] : []
    rescue StandardError => e
      ["law: #{e.class}: #{e.message}"]
    end

    def law_catalogue_issues
      require File.join(@root, "MASTER", "lib", "master") unless defined?(Master::ROOT)
      require File.join(@root, "MASTER", "lib", "review", "scan", "law_registry_audit")
      report = Master::Review::Scan::LawRegistryAudit.new(root: File.join(@root, "MASTER")).call
      report.assert_catalogue_integrity!
      []
    rescue StandardError => e
      ["law: catalogue integrity failed - #{e.class}: #{e.message}"]
    end

    def tree_authority_issues
      issues = []
      rails_tokens = File.join(@root, "RAILS/__shared/design_tokens.yml")
      if File.file?(rails_tokens)
        header = File.read(rails_tokens).lines.first(2).join
        issues << "rails: generated design tokens lost MASTER source marker" unless header.include?("MASTER/data/tokens.yml")
      end
      issues << "openbsd: missing operator recipe authority" unless File.file?(File.join(@root, "OPENBSD/data/operator.yml"))
      issues
    end
  end
end
