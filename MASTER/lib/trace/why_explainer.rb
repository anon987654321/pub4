# frozen_string_literal: true

module Master
  module Trace
  # Local lookup for /why <id>; falls back to LLM when nothing matches.
    class WhyExplainer
      SCAN_RULES_DIR = "lib/review/scan/rules"

      def initialize(root: Master::ROOT)
        @root = root
      end

      def explain(id)
        key = id.to_s.strip
        return if key.empty?

        law(key) ||
          registry_rule(key) ||
          soul_rule(key) ||
          scan_rule(key) ||
          anti_pattern(key) ||
          style_key(key)
      end

      private

      def rules
        @rules ||= begin
          base = Master.load_yaml(File.join(@root, "data", "rules.yml")) || {}
          base["rules"] = load_split_rules
          base
        end
      end

      def load_split_rules
        dir = File.join(@root, "data", "rules")
        return {} unless File.directory?(dir)

        Dir.glob(File.join(dir, "*.yml")).sort.each_with_object({}) do |path, merged|
          data = Master.load_yaml(path) || {}
          data.each { |scope, items| (merged[scope] ||= []).concat(Array(items)) }
        end
      end

      def soul
        @soul ||= Master.load_yaml(File.join(@root, "data", "soul.yml")) || {}
      end

      def style
        @style ||= Master.load_yaml(Master.style_path) || {}
      end

      def registry_rule(key)
        slug = key.upcase.tr("-", "_")
        hit = Master.flatten_rules(rules.fetch("rules", {})).find { |r| r["id"].to_s.upcase == slug }
        return unless hit

        [
          "rule: #{hit['id']}",
          ("  tier: #{hit['tier']}" if hit["tier"]),
          ("  name: #{hit['name']}" if hit["name"]),
          ("  source: #{hit['source']}" if hit["source"]),
          ("  fix: #{hit['fix']}" if hit["fix"]),
        ].compact.join("\n")
      end

      def soul_rule(key)
        slug = key.upcase.tr("-", "_")
        hit = soul.dig("absolute", "code_rules", slug) or return
        ["constitutional rule: #{slug}", "  #{hit}"].join("\n")
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
        return registry_rule(slug) unless File.file?(path)

        src = File.read(path)
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

          cursor = cursor[k]
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
