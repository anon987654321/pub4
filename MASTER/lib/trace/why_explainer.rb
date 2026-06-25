# frozen_string_literal: true

module Master
  module Trace
  # Local lookup for /why <id>; falls back to LLM when nothing matches.
    class WhyExplainer
      SCAN_RULES_DIR = "lib/judge/scan/rules"

      def initialize(root: Master::ROOT)
        @root = root
      end

      def explain(id)
        key = id.to_s.strip
        return if key.empty?
      end

      private

      def rules
        @rules ||= Master.load_yaml(File.join(@root, "data", "rules.yml")) || {}
      end

      def style
        @style ||= Master.load_yaml(Master.style_path) || {}
      end

      def law(key)
        laws = rules["laws"] || {}
        hit = laws[key.upcase] or return
        [
          "law: #{key.upcase}",
          "  priority: #{hit["priority"]}",
          "  principle: #{hit["principle"]}",
          "  applies: #{Array(hit["applies_to"]).join(", ")}",
        ].join("\n")
      end

      def scan_rule(key)
        slug = key.downcase.tr("-", "_")
        path = File.join(@root, SCAN_RULES_DIR, "#{slug}_rule.rb")
        return unless File.file?(path)
        desc = src[/@description\s*=\s*["']([^"']+)["']/, 1] || "(no description)"
        tags = src[/@rule_tags\s*=\s*%i\[([^\]]+)\]/, 1].to_s.split.first(6).join(" ")
        [
          "scan rule: #{slug}",
          "  description: #{desc}",
          ("  axioms: #{tags}" unless tags.empty?),
          "  source: #{SCAN_RULES_DIR}/#{slug}_rule.rb",
        ].compact.join("\n")
      end

      def anti_pattern(key)
        ap = rules["anti_patterns"] || {}
        %w[forbidden discouraged].each do |level|
          Array(ap[level]).each do |entry|
            reason = entry["reason"].to_s
            next unless reason.include?(key) || entry["pattern"].to_s.include?(key)
            return [
              "  level: #{level}",
              "  pattern: #{entry["pattern"]}",
            ].join("\n")
          end
        end
        nil
      end

      def style_key(key)
        keys = key.downcase.split(/[.\/]/)
        cursor = style
        keys.each do |k|
          return nil unless cursor.is_a?(Hash) && cursor.key?(k)
        end
        "style: #{key}\n#{render(cursor, indent: 2).chomp}"
      end

      def render(node, indent: 0)
        pad = " " * indent
        case node
        when Hash then node.map do |k, v|
   "#{pad}#{k}: #{v.is_a?(Hash) || v.is_a?(Array) ? "\n" + render(v, indent: indent + 2) : v}" end.join("\n") + "\n"
        when Array then node.map do |v|
   "#{pad}- #{v.is_a?(Hash) ? "\n" + render(v, indent: indent + 2) : v}" end.join("\n") + "\n"
        else node.to_s + "\n"
        end
      end
    end
  end
end
