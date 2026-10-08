# frozen_string_literal: true

require "yaml"

module Operator
  class ConstitutionContract
    ROOT = File.expand_path("../../..", __dir__)
    REQUIRED = %w[
      MASTER/data/soul.yml
      MASTER/data/laws.yml
      MASTER/data/SOUL.md
      MASTER/data/project_context.yml
      MASTER/bin/cli
      MASTER/lib/review/scan
      MASTER/law/law.rb
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
      soul = load_yaml("MASTER/data/soul.yml")
      laws = load_yaml("MASTER/data/laws.yml")
      issues << "soul: golden rule missing or changed" unless soul.dig("absolute", "golden_rule") == "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      issues << "soul: no sacred paths declared" unless Array(soul.dig("absolute", "sacred_paths")).any?
      issues << "rules: missing design tokens" unless laws["tokens"].is_a?(Hash)
      declared = laws.any? { |_id, value| value.is_a?(Hash) && value["priority"] && value["principle"] }
      issues << "rules: no declared policy laws" unless declared
      prose = File.join(@root, "MASTER", "law", "prose.rb")
      issues << "rules: no Bringhurst reference" unless File.file?(prose) && File.read(prose).include?("Bringhurst")
      issues.concat(law_issues)
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
      require File.join(@root, "MASTER", "law", "law")
      ::Law.load_all(File.join(@root, "MASTER", "law")) if ::Law.definitions.empty?
      ::Law.definitions.empty? ? ["law: no executable rules loaded"] : []
    rescue StandardError => e
      ["law: #{e.class}: #{e.message}"]
    end

    def tree_authority_issues
      issues = []
      rails_tokens = File.join(@root, "RAILS/__shared/design_tokens.yml")
      if File.file?(rails_tokens)
        header = File.read(rails_tokens).lines.first(2).join
        issues << "rails: generated design tokens lost MASTER source marker" unless header.include?("MASTER/data/laws.yml")
      end
      issues << "openbsd: missing operator recipe authority" unless File.file?(File.join(@root, "OPENBSD/data/operator.yml"))
      issues
    end
  end
end
