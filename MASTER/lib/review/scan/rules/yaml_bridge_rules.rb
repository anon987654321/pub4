# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules
        # Bridges rules.yml veto_patterns into the scanner (constitution.rb also checks writes).
        class VetoPatternRule < Rule
          def self.auto_build? = false

          def initialize(root: Master::ROOT)
            super()
            @id = "veto_patterns"
            @description = "Unconditional merge blockers from rules.yml veto_patterns"
            @severity = :veto
            @auto_fix = false
            @patterns = load_patterns(root)
          end

          def check(code, path:)
            return [] if @patterns.empty?

            @patterns.flat_map do |name, spec|
              detect = spec["detect"]
              next [] unless detect

              regex = detect.is_a?(String) ? Regexp.new(detect) : detect
              # unfinished is the one pattern that means to read comments, because
              # that is where a work marker lives. Every other veto is about code,
              # and a comment describing a shell interpolation is documentation.
              # (Written without naming the markers, since this rule reads it.)
              source = spec["reads_comments"] ? code : without_comment_lines(code)
              scan_lines(source, regex, message: "veto: #{name} — #{spec["apply"] || "blocked"}")
            end
          end

          private

          # #check returns [] for every file when the pattern set is empty,
          # which reads as a tree with no veto violations. An unreadable
          # rules.yml retires every veto at once, so say so.
          def load_patterns(root)
            data = Master.load_yaml(File.join(root, "data", "rules.yml")) || {}
            data.fetch("veto_patterns", {})
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "VetoPatternRule.load_patterns", severity: :load_bearing)
            {}
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
        # Wires rules.yml detect_lexical entries not already covered by RuleDSL classes.
        class YamlDeclarativeRule < Rule
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

              declarative_hits(code, entry).map do |hit|
                Finding.build(
                  rule: entry[:id].to_s.downcase,
                  message: hit.message,
                  line: hit.line,
                  severity: entry[:severity],
                  tags: [entry[:id].to_s.upcase],
                )
              end
            end
          end

          private

          def reload!
            return if self.class.reloading?

            self.class.reloading = true
            registry_ids = build_registry_ids
            yaml_rules = Master.flatten_rules(Master.load_rules(root: @root).fetch("rules", {}))
            @entries = build_lexical_entries(yaml_rules, registry_ids)
            @mtime = rules_mtime
          ensure
            self.class.reloading = false
          end

          def build_registry_ids
            Review::Scan::Rule.registry
              .reject { |klass| RuleFactory.bridge_class?(klass) }
              .filter_map { |klass| RuleFactory.registry_id(klass, root: @root) }
              .to_set
          end

          def build_lexical_entries(yaml_rules, registry_ids)
            yaml_rules
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
              rescue RegexpError => e
                # A rule declared in rules.yml with an uncompilable regex is
                # inert law: listed, counted, never run. Drop it, but say which.
                Master::Ground::Swallow.log(e, context: "YamlDeclarativeRule #{r["id"]}", severity: :load_bearing)
                nil
              end
          end

          def reload_if_stale
            reload! if @mtime != rules_mtime
          end

          def rules_mtime
            path = File.join(@root, "data", "rules.yml")
            File.exist?(path) ? File.mtime(path).to_i : nil
          end

          def declarative_hits(code, entry)
            message = "#{entry[:id]}: #{entry[:fix] || entry[:name]}"
            if entry[:regex].source.include?("\\A")
              code.match?(entry[:regex]) ? [finding(line: 1, message:)] : []
            else
              scan_lines(without_comment_lines(code), entry[:regex], message:)
            end
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
