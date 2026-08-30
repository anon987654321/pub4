# frozen_string_literal: true

require "pathname"
require "yaml"

module Master
  module Ground
    module Antigravity
      # Rules manages hierarchical Antigravity rules (GEMINI.md, AGENTS.md, .agents/rules/*.md,
      # and plugin rules) with deduplication, precedence, and progressive disclosure.
      class Rules
        RULE_FILENAMES = %w[GEMINI.md AGENTS.md].freeze

        attr_reader :discovery

        def initialize(discovery: Discovery.new)
          @discovery = discovery
        end

        def discover_rules(target_path: @discovery.cwd)
          start_dir = File.directory?(target_path) ? target_path : File.dirname(target_path)
          current = Pathname.new(File.expand_path(start_dir))
          repo_root = Pathname.new(@discovery.workspace_root)
          stop_at = repo_root.parent

          discovered_paths = []

          # 1. Walk upwards from current dir to repo root
          while current && current != stop_at && !current.root?
            RULE_FILENAMES.each do |filename|
              file = current + filename
              discovered_paths << file.to_s if file.file?
            end

            Discovery::WORKSPACE_ROOT_DIRS.each do |dir_name|
              rules_dir = current + dir_name + "rules"
              if rules_dir.directory?
                Dir.glob(File.join(rules_dir.to_s, "*.md")).sort.each do |rule_file|
                  discovered_paths << rule_file if File.file?(rule_file)
                end
              end
            end

            break if current == repo_root
            current = current.parent
          end

          # Deduplicate by resolved realpath
          dedup_paths(discovered_paths)
        end

        def load_all_rules(target_path: @discovery.cwd)
          paths = discover_rules(target_path:)
          paths.map { |p| parse_rule_file(p) }.compact
        end

        def active_rules_prompt(target_path: @discovery.cwd, model_decisions: [])
          rules = load_all_rules(target_path:)
          active = rules.select do |rule|
            rule[:trigger] == "always_on" || model_decisions.include?(rule[:name])
          end
          return nil if active.empty?

          active.map do |rule|
            header = "### Rule: #{rule[:name]} (#{rule[:path]})"
            "#{header}\n\n#{rule[:body]}"
          end.join("\n\n---\n\n")
        end

        private

        def dedup_paths(paths)
          seen = {}
          paths.each_with_object([]) do |path, result|
            real = begin
              File.realpath(path)
            rescue StandardError
              File.expand_path(path)
            end
            unless seen[real]
              seen[real] = true
              result << path
            end
          end
        end

        def parse_rule_file(path)
          content = File.read(path, encoding: "UTF-8")
          match = content.match(/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m)

          if match
            meta = begin
              YAML.safe_load(match[1], aliases: false) || {}
            rescue StandardError
              {}
            end
            body = match[2].to_s.strip
            name = meta["name"] || File.basename(path, ".md")
            trigger = meta.fetch("trigger", "always_on").to_s
            { name:, trigger:, body:, path:, meta: }
          else
            name = File.basename(path, ".md")
            { name:, trigger: "always_on", body: content.strip, path:, meta: {} }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.rules.parse", path:)
          nil
        end
      end
    end
  end
end
