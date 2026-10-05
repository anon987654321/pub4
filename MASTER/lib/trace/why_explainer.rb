# frozen_string_literal: true

require_relative "rule_lineage"

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

        rule_lineage(key) ||
          design_law(key) ||
          law(key) ||
          # The declared rule first: it carries tier and name, and registry_rule
          # borrows the executable law's fix when the declaration has none. An
          # executable law answers for the ids nothing declared.
          registry_rule(key) ||
          soul_rule(key) ||
          executable_law(key) ||
          scan_rule(key) ||
          anti_pattern(key) ||
          style_key(key)
      end

      private

      def rule_lineage(key)
        return unless key.include?("/") || File.exist?(File.join(@root, key))

        RuleLineage.new(root: @root).explain(key)
      end

      # The design law. It sits at laws.yml#beauty, line 92 of 4,215, and an
      # agent finds it only if a human points -- which is how it was found on
      # 2026-08-31. Ando, Rams and Zen govern every visual decision in this tree
      # and nothing surfaced them.
      def design_law(key)
        return unless %w[beauty design design_law aesthetic].include?(key.downcase)

        b = rules["beauty"] || {}
        return if b.empty?

        lines = ["design law (data/laws.yml#beauty) — governs every visual decision:"]
        b.each do |group, values|
          lines << "  #{group}:"
          case values
          when Hash then values.each { |k, v| lines << "    #{k}: #{v}" }
          else Array(values).each { |v| lines << "    #{v}" }
          end
        end
        lines.join("\n")
      end

      # Master.load_laws, not a private re-read. This method used to load
      # laws.yml and then overwrite base["rules"] with its own copy of the
      # shard-merge loop — a second implementation of Master.load_laws living
      # two directories away. When the shards were folded into laws.yml on
      # 2026-08-12 that copy started returning {} and assigning it over the real
      # rules, so /why went silent for every registry and scan rule while
      # reporting nothing wrong.
      def rules
        @rules ||= Master.load_laws(root: @root)
      end

      def soul
        @soul ||= Master.load_yaml(File.join(@root, "data", "soul.yml")) || {}
      end

      def style
        @style ||= Master.law("style", root: @root)
      end

      def executable_law(key)
        slug = key.upcase.tr("-", "_")
        require File.join(@root, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(@root, "law"))
        hit = ::Law.rules[slug.to_sym]
        return unless hit

        [
          "executable law: #{slug}",
          ("  source: #{hit.source}" if hit.source),
          "  severity: #{hit.severity}",
          ("  mode: #{hit.mode}" if hit.mode),
          ("  practice: #{hit.practice}" if hit.practice),
          ("  ask: #{hit.ask}" if hit.ask),
          "  fix: #{hit.fix}",
        ].compact.join("\n")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WhyExplainer.executable_law", severity: :cosmetic)
        nil
      end

      def registry_rule(key)
        slug = key.upcase.tr("-", "_")
        hit = Master.law_entries(root: @root).find { |r| r["id"].to_s.upcase == slug }
        return unless hit

        [
          "rule: #{hit['id']}",
          ("  tier: #{hit['tier']}" if hit["tier"]),
          ("  name: #{hit['name']}" if hit["name"]),
          ("  source: #{hit['source']}" if hit["source"]),
          ("  fix: #{hit["fix"]}" if hit["fix"] || begin
            executable = ::Law.rules[slug.to_sym] if defined?(::Law)
            executable&.fix
          end),
        ].compact.join("\n")
      end

      def soul_rule(key)
        slug = key.upcase.tr("-", "_")
        # law/ holds every rule now, so /why answers for conduct rules too —
        # it dug soul and returned nothing for NO_COLUMN_ALIGN and FLAT_UI.
        hit = Master::Ground::Rules.new.rules[slug] or return
        ["constitutional rule: #{slug}", "  #{hit}"].join("\n")
      end

      def law(key)
        hit = Master.law_entries(root: @root).find { |law| law["id"].to_s.upcase == key.upcase } or return
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
          return unless cursor.is_a?(Hash) && cursor.key?(k)

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
