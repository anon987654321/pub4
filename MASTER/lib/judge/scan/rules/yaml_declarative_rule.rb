# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules
        # Wires rules.yml detect_lexical entries not already covered by RuleDSL classes.
        class YamlDeclarativeRule < Rule
          BRIDGE_CLASSES = %w[YamlDeclarativeRule VetoPatternRule].freeze

          def self.auto_build? = false

          def self.reloading?
            @reloading
          end

          def self.reloading=(value)
            @reloading = value
          end

          def initialize(root: Master::ROOT)
            super()
            @id = "yaml_declarative"
            @description = "YAML detect_lexical bridge for unwired declarative rules"
            @severity = :warning
            @auto_fix = false
            @root = root
            reload!
          end

          def check(code, path:)
            reload_if_stale
            return [] if @entries.empty?

            rel = path.delete_prefix("#{@root}/")
            @entries.flat_map do |entry|
              next [] unless applies?(entry, path, rel)
              next [] unless entry[:regex]

              scan_lines(code, entry[:regex], message: "#{entry[:id]}: #{entry[:fix] || entry[:name]}")
                .map do |hit|
                  Finding.build(
                    rule: entry[:id].to_s.downcase,
                    message: hit.message,
                    line: hit.line,
                    severity: entry[:severity],
                    tags: [entry[:id].to_s.upcase]
                  )
                end
            end
          end

          private

          def reload!
            return if self.class.reloading?

            self.class.reloading = true
            registry_ids = Judge::Scan::Rule.registry
              .reject { |klass| bridge_class?(klass) }
              .filter_map { |klass| registry_rule_id(klass) }
              .to_set
            data = Master.load_yaml(File.join(@root, "data", "rules.yml")) || {}
            yaml_rules = flatten_rules_body(data["rules"])
            @entries = yaml_rules
              .select { |r| r["detect_lexical"] && !registry_ids.include?(r["id"].to_s.downcase) }
              .filter_map do |r|
                {
                  id: r["id"],
                  name: r["name"],
                  fix: r["fix"],
                  severity: (r["severity"] || "warning").to_sym,
                  regex: Regexp.new(r["detect_lexical"]),
                  languages: Array(r["languages"]),
                  path_match: r["path_match"],
                }
              rescue RegexpError
                nil
              end
            @mtime = rules_mtime
          ensure
            self.class.reloading = false
          end

          def reload_if_stale
            reload! if @mtime != rules_mtime
          end

          def rules_mtime
            File.mtime(File.join(@root, "data", "rules.yml")).to_i
          rescue StandardError
            nil
          end

          def bridge_class?(klass)
            name = klass.name.to_s
            BRIDGE_CLASSES.any? { |token| name.include?(token) }
          end

          def flatten_rules_body(body)
            case body
            when Hash then body.values.flatten
            when Array then body
            else []
            end
          end

          def registry_rule_id(klass)
            return klass.new.id.to_s.downcase if klass.auto_build?

            case klass.name
            when /CoChangeCouplingRule/ then "co_change_coupling"
            when /RuleCoverageRule/ then "rule_coverage"
            when /RubocopRule/ then "rubocop"
            when /ReekRule/ then "reek"
            when /InterconnectRule/ then "interconnect"
            when /SemanticRule/ then "semantic"
            when /AdversarialRule/ then "adversarial"
            when /CommentDriftRule/ then "comment_drift"
            when /AstOmissionRule/ then "ast_omission"
            when /LearnedSmellsRule/ then "learned_smells"
            else
              short = klass.name.to_s.split("::").last.to_s.delete_suffix("Rule")
              short.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
            end
          rescue StandardError
            nil
          end

          def applies?(entry, path, rel)
            if entry[:path_match] && !rel.include?(entry[:path_match].to_s.delete("/"))
              return false
            end
            langs = entry[:languages]
            return true if langs.empty?

            applies_to?(path, langs)
          end
        end
      end
    end
  end
end