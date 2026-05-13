# frozen_string_literal: true

module Master
  module Introspection
    class SelfMap
      AXIOM_FALLBACK = %w[
        PRESERVE_FIRST SIMPLEST_WORKS FAIL_VISIBLY EXPLICIT IMMUTABLE
        CQS SELF_EXPLAINING SINGLE_RESPONSIBILITY NO_HARDCODING GUARD_FIRST
      ].freeze

      def initialize(root:)
        @root = root
      end

      def describe
        files = Dir.glob(File.join(@root, "lib/**/*.rb"))
        lines = files.sum { |f| File.read(f, encoding: "UTF-8").lines.size rescue 0 }
        { files: files.size, lines: lines }
      end

      def rule_coverage
        tags = load_rule_tags
        src  = Dir.glob(File.join(@root, "lib/**/*.rb"))
                  .map { |f| File.read(f, encoding: "UTF-8") rescue "" }
                  .join("\n")
        tags.each_with_object({}) { |ax, h| h[ax] = src.scan(/\b#{Regexp.escape(ax)}\b/).size }
      end

      private

      def load_rule_tags
        rules_path = File.join(@root, "data", "rules.yml")
        data = Master.load_yaml(rules_path)
        tags = (data["rules"] || {}).keys
        tags.empty? ? AXIOM_FALLBACK : tags
      rescue StandardError => _e
        AXIOM_FALLBACK
      end
    end
  end
end
