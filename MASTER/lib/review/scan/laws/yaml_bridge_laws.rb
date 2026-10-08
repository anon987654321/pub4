# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Laws
        # Bridges laws.yml veto_patterns into the scanner (constitution.rb also checks writes).
        #
        # A veto is the severity above error, and this was the one rule in the
        # population with no exemption of any kind — so it read the scanner's own
        # rule sources as conduct where every registered twin of these patterns
        # skips that directory by name. All four of its findings under lib/ and
        # law/ were worked examples: the work marker TODO_FIXME and
        # NO_TODO_IN_VIEWS each carry, SQL_INJECTION's interpolated query and the
        # quoted fix beside it. Only the `fires:`/`does_not_fire:` lines are
        # blanked, not the directory, so a real secret or shell interpolation in
        # a rule file still vetoes.
        class VetoPatternLaw < Law
          def self.auto_build? = false

          declare id: "veto_patterns", severity: :veto,
                  description: "Unconditional merge blockers from laws.yml veto_patterns"

          def initialize(root: Master::ROOT)
            super()
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
              source = without_rule_fixtures(source) if path.to_s.include?("/review/scan/rules/")
              scan_lines(source, regex, message: "veto: #{name} — #{spec["apply"] || "blocked"}")
            end
          end

          private

          # #check returns [] for every file when the pattern set is empty,
          # which reads as a tree with no veto violations. An unreadable
          # laws.yml retires every veto at once, so say so.
          def load_patterns(root)
            (Master.load_laws(root:) || {}).fetch("veto_patterns", {})
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "VetoPatternLaw.load_patterns", severity: :load_bearing)
            raise
          end
        end

        # Wires laws.yml detect_lexical entries not already covered by LawDSL classes.
        class YamlDeclarativeLaw < Law
          def self.auto_build? = false

          declare id: "yaml_declarative", severity: :warning,
                  description: "YAML detect_lexical bridge for unwired declarative rules"

          def initialize(root: Master::ROOT)
            super()
            @root = root
            @reload_mutex = Mutex.new
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
                  law: entry[:id].to_s.downcase,
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
            @reload_mutex.synchronize do
              stamp = rules_mtime
              return if @entries && @mtime == stamp

              registry_ids = build_registry_ids
              yaml_rules = Master.law_entries(root: @root)
              @entries = build_lexical_entries(yaml_rules, registry_ids)
              @mtime = stamp
            end
          end

          def build_registry_ids
            Review::Scan::Law.registry
              .reject { |klass| LawFactory.bridge_class?(klass) }
              .filter_map { |klass| LawFactory.registry_id(klass, root: @root) }
              .to_set
          end

          def build_lexical_entries(yaml_rules, registry_ids)
            law_ids = defined?(::Law) ? ::Law.definitions.keys.map(&:to_s).to_set : Set.new
            yaml_rules
              .select { |r| r["detect_lexical"] && !registry_ids.include?(r["id"].to_s.downcase) }
              .reject { |r| law_ids.include?(r["id"].to_s) } # law/ owns it now
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
                # A rule declared in laws.yml with an uncompilable regex is
                # inert law: listed, counted, never run. Drop it, but say which.
                Master::Ground::Swallow.log(e, context: "YamlDeclarativeLaw #{r["id"]}", severity: :load_bearing)
                nil
              end
          end

          def reload_if_stale
            reload!
          end

          def rules_mtime
            path = File.join(@root, "data", "laws.yml")
            return unless File.exist?(path)

            stat = File.stat(path)
            [stat.size, stat.ino, stat.mtime.to_r]
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
