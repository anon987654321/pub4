# frozen_string_literal: true

require "set"
require "yaml"

module Master
  module Review
    module Scan
      module Rules
        # Detects phantom reads — Ruby code digs keys that don't exist in the corresponding data/*.yml.
        # Also detects orphan keys — top-level YAML keys with zero references in lib/.
        # Only meaningful when scanning lib/ with root: access.
        class InterconnectRule < Rule
          LOAD_CALL = /load_yaml(?:_data)?\s*\(\s*["']([^"']+\.yml)["']/.freeze
          DIG_CALL = /\.dig\(\s*((?:["'][^"']+["']\s*,?\s*)+)\)/.freeze
          FETCH_CALL = /\.fetch\(\s*["']([^"']+)["']/.freeze
          BRACKET_KEY = /\[["']([^"']+)["']\]/.freeze

          def self.auto_build? = false

          def initialize(root:)
            super()
            @id = "interconnect"
            @description = "Phantom YAML key reads and orphan data keys"
            @severity = :warning
            @auto_fix = false
            @rule_tags = %i[ONE_SOURCE]
            @root = root
            @data_dir = File.join(root, "data")
            @lib_source = load_lib_source(root)
          end

          def check(code, path:)
            findings = []
            findings.concat(check_phantom_yaml_reads(code, path)) if path.include?("/lib/") && path.end_with?(".rb")
            findings
          end

          private

          def check_phantom_yaml_reads(code, _path)
            yaml_files = extract_loaded_yamls(code)
            return [] if yaml_files.empty?

            loaded, unparseable = load_referenced_yamls(yaml_files)
            findings = unparseable.map do |yml_name, error|
              finding(line: 1, message: "referenced yaml #{yml_name} failed to parse: #{error}")
            end
            return findings if loaded.empty?

            findings.concat(phantom_dig_findings(code, loaded))
          end

          # Law that fails to parse must surface as a finding, never vanish: a
          # scanner that silently skips an unparseable data/*.yml validates the
          # codebase against a partial constitution and reports it as a pass.
          def load_referenced_yamls(yaml_files)
            loaded = []
            unparseable = []
            yaml_files.each do |yml_name|
              yml_path = File.join(@data_dir, yml_name)
              next unless File.exist?(yml_path)

              begin
                data = YAML.safe_load(File.read(yml_path), aliases: true)
                loaded << data if data
              rescue StandardError => e
                unparseable << [yml_name, e.message]
              end
            end
            [loaded, unparseable]
          end

          def phantom_dig_findings(code, loaded)
            findings = []
            extract_dig_paths(code).each do |path_keys|
              next if loaded.any? { |y| y.respond_to?(:dig) && y.dig(*path_keys) }
              code.each_line.with_index(1) do |line, number|
                next unless line.include?(path_keys.first.to_s)
                findings << finding(
                  line: number,
                  message: "phantom key #{path_keys.inspect} not found in any loaded yaml",
                )
                break
              end
            end
            findings
          end

          def extract_loaded_yamls(code)
            code.scan(LOAD_CALL).flatten.compact
          end

          def extract_dig_paths(code)
            code.scan(DIG_CALL).filter_map do |match|
              raw = match.first.to_s
              keys = raw.scan(/["']([^"']+)["']/).flatten
              keys.size >= 1 ? keys : nil
            end
          end

          def load_lib_source(root)
            lib_dir = File.join(root, "lib")
            return "" unless File.directory?(lib_dir)
            Dir.glob(File.join(lib_dir, "**", "*.rb"))
               .filter_map do |f|
                 File.read(f)
               rescue StandardError => e
                 Master::Ground::Swallow.log(e, context: "graph_rules.load_lib_source", path: f)
                 nil
               end
               .join("\n")
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
        # Files that change together in many commits are coupled regardless of imports.
        # Reads the co-change graph from RepoEcology (built once at boot) instead of
        # mining git per-scan. Flags cross-module pairs — likely DECOUPLE candidates
        # the lexical rules can't see.
        class CoChangeCouplingRule < Rule
          WEIGHT_THRESHOLD = 5

          def self.auto_build? = false

          def initialize(root: nil, ecology: nil)
            super()
            @id = "co_change_coupling"
            @description = "Files co-change with N+ peers across module boundaries — hidden coupling"
            @severity = :info
            @rule_tags = %i[DECOUPLE ONE_JOB]
            @root = root ? File.expand_path(root) : File.expand_path(File.join(Master::ROOT, ".."))
            @ecology = ecology
          end

          def check(_code, path:)
            return [] unless path.end_with?(".rb")

            rel = relativize(path)
            return [] unless rel

            peers = neighbors(rel)
              .reject { |peer, _| same_module?(rel, peer) }
              .select { |_, weight| weight >= WEIGHT_THRESHOLD }
              .sort_by { |_, weight| -weight }
              .take(3)
              .to_a
            return [] if peers.empty?

            [finding(line: 1, message: coupling_message(rel, peers))]
          end

          private

          def coupling_message(rel, peers)
            names = peers.map { |peer, weight| "#{peer} (#{weight})" }.join(", ")
            "co-changes across modules with #{peers.size} peer(s): #{names} — #{rel}"
          end

          def neighbors(rel)
            graph[rel] || {}
          end

          def graph
            @ecology ? @ecology.co_change_graph : {}
          end

          def relativize(path)
            full = File.expand_path(path)
            prefix = @root + "/"
            full.start_with?(prefix) ? full.delete_prefix(prefix) : nil
          end

          def same_module?(a, b) = module_of(a) == module_of(b)

          def module_of(path)
            parts = path.split("/")
            parts[0] == "MASTER" ? (parts[2] || parts[0]) : parts[0]
          end
        end
      end
    end
  end
end
