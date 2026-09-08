# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "yaml"

module Master
  module Ground
    # Reads the skills an Antigravity workspace declares — `.agents/skills/`,
    # a `skills.json` and its inherits chain, and the global and built-in roots
    # under `~/.gemini` — so `Cli::Skills` can offer them beside MASTER's own.
    # That is the whole surface: skills in, skill hashes out.
    #
    # It is an adapter to somebody else's on-disk format
    # (https://antigravity.google/docs/home/), not a second skills system, and
    # nothing here decides anything. The `agy` provider in `data/providers.yml`
    # is a different subject that shares the name — that one is an LLM reached
    # by executing a binary.
    module Antigravity
      # JsonConfig parses the Antigravity skills.json schema, resolving inherits,
      # entries, path resolution, and regex filtering.
      class JsonConfig
        def self.load(file_path, workspace_root: nil, visited: [])
          new(file_path, workspace_root:, visited:).resolve_entries
        end

        def initialize(file_path, workspace_root: nil, visited: [])
          @file_path = File.expand_path(file_path)
          @workspace_root = workspace_root || Dir.pwd
          @visited = visited
        end

        # Inherited entries first, then local ones: a config's own entries take
        # precedence over what it inherits, and the caller keeps the last of a
        # duplicate name.
        def resolve_entries
          return [] if @visited.include?(@file_path) || !File.file?(@file_path)

          data = parse_json(@file_path)
          return [] unless data.is_a?(Hash)

          inherited_entries(Array(data["inherits"])) + local_entries(Array(data["entries"]))
        end

        def resolve_path(path_str)
          return path_str if path_str.start_with?("/")
          return File.expand_path(path_str) if path_str.start_with?("~/")

          File.expand_path(path_str, @workspace_root)
        end

        private

        def inherited_entries(specs)
          visited = @visited + [@file_path]
          specs.flat_map do |spec|
            next [] unless spec.is_a?(Hash)

            path = spec["path"].to_s
            next [] if path.empty?

            loaded = self.class.load(resolve_path(path), workspace_root: @workspace_root, visited:)
            filter_entries(loaded, include_only: spec["include_only"], exclude: spec["exclude"])
          end
        end

        def local_entries(specs)
          specs.filter_map do |spec|
            next unless spec.is_a?(Hash)

            path = spec["path"].to_s
            next if path.empty?

            { path: resolve_path(path),
              include_only: Array(spec["include_only"]),
              exclude: Array(spec["exclude"]) }
          end
        end

        def parse_json(path)
          JSON.parse(File.read(path, encoding: "UTF-8"))
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.json_config.parse", path:)
          nil
        end

        def filter_entries(entries, include_only:, exclude:)
          inc_patterns = Array(include_only).map { |p| Regexp.new(p) }
          exc_patterns = Array(exclude).map { |p| Regexp.new(p) }

          entries.select do |entry|
            base = File.basename(entry[:path])
            matches_inc = inc_patterns.empty? || inc_patterns.any? { |r| r.match?(base) }
            matches_exc = exc_patterns.any? { |r| r.match?(base) }
            matches_inc && !matches_exc
          end
        end
      end

      # Discovery traverses directory trees and discovers Antigravity customization roots
      # across workspace projects, declared configs, global and built-in paths.
      class Discovery
        WORKSPACE_ROOT_DIRS = %w[.agents .agent _agents _agent].freeze
        GLOBAL_CONFIG_PATH = "~/.gemini/config"
        BUILTIN_PATH = "~/.gemini/antigravity-cli/builtin"

        attr_reader :workspace_root, :cwd

        def initialize(cwd: Dir.pwd, workspace_root: nil)
          @cwd = File.expand_path(cwd)
          @workspace_root = workspace_root ? File.expand_path(workspace_root) : find_repo_root(@cwd)
        end

        def find_repo_root(start_dir)
          current = Pathname.new(start_dir)
          loop do
            return current.to_s if (current + ".git").exist? || (current + ".agents").exist?
            break if current.root?

            current = current.parent
          end
          start_dir
        end

        # Discovers all active customization directories in precedence order:
        # 1. Workspace Project (.agents/)
        # 2. Declared JSON configs (skills.json in workspace)
        # 3. Global Discovery (~/.gemini/config/)
        # 4. Built-in Customizations (~/.gemini/antigravity-cli/builtin/)
        # 5. Global Declared JSON configs
        def workspace_customization_roots
          roots = []
          current = Pathname.new(@cwd)
          stop_at = Pathname.new(@workspace_root).parent

          while current && current != stop_at && !current.root?
            WORKSPACE_ROOT_DIRS.each do |name|
              candidate = current + name
              roots << candidate.to_s if candidate.directory?
            end
            current = current.parent
          end
          roots.uniq
        end

        def global_customization_root
          expanded = File.expand_path(GLOBAL_CONFIG_PATH)
          File.directory?(expanded) ? expanded : nil
        end

        def builtin_customization_root
          expanded = File.expand_path(BUILTIN_PATH)
          File.directory?(expanded) ? expanded : nil
        end

        def declared_skills_entries
          entries = []
          workspace_customization_roots.each do |root|
            cfg = File.join(root, "skills.json")
            entries.concat(JsonConfig.load(cfg, workspace_root: @workspace_root)) if File.file?(cfg)
          end
          entries
        end

      end

      # Skills discovers, validates, and manages Antigravity workspace skills, plugin skills,
      # global skills, and built-in skills with progressive disclosure.
      class Skills
        attr_reader :discovery, :skills

        def initialize(discovery: Discovery.new, usage_file: nil)
          @discovery = discovery
          @usage_file = usage_file || File.expand_path("~/.gemini/antigravity-cli/skill_usage.yml")
          @skills = {}
          @usage = load_usage
        end

        def discover!
          @skills = {}

          # 5. Global Declared & Built-in Customizations (lowest precedence)
          if @discovery.builtin_customization_root
            scan_skills_dir(File.join(@discovery.builtin_customization_root, "skills"), source: :builtin)
          end

          # 3. Global Discovery (~/.gemini/config/skills/)
          if @discovery.global_customization_root
            scan_skills_dir(File.join(@discovery.global_customization_root, "skills"), source: :global)
          end

          # 2. Declared JSON configs (skills.json)
          @discovery.declared_skills_entries.each do |entry|
            scan_skills_dir(entry[:path], source: :declared, include_only: entry[:include_only], exclude: entry[:exclude])
          end

          # 1. Workspace Project (.agents/skills/) (highest precedence)
          @discovery.workspace_customization_roots.reverse_each do |root|
            scan_skills_dir(File.join(root, "skills"), source: :workspace)
          end

          @skills.values.sort_by { |s| [-@usage.fetch(s[:name], 0).to_i, s[:name]] }
        end

        def list
          discover!
        end

        def find(name)
          discover! if @skills.empty?
          @skills[name.to_s]
        end

        def body_for(name)
          skill = find(name)
          return nil unless skill

          read_skill_body(skill)
        end

        def reference_for(name, reference_rel_path)
          skill = find(name)
          return nil unless skill

          ref_path = File.expand_path(reference_rel_path, skill[:dir])
          return nil unless File.file?(ref_path) && ref_path.start_with?(skill[:dir])

          File.read(ref_path, encoding: "UTF-8")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.skills.reference_for", name:, reference_rel_path:)
          nil
        end

        def record_used(name)
          @usage[name.to_s] = Time.now.to_i
          persist_usage
        end

        # Progressive disclosure summary for system prompts
        def prompt_catalog
          skills_list = list
          return nil if skills_list.empty?

          items = skills_list.map do |s|
            "- #{s[:name]} (#{s[:skill_file]}): #{s[:description]}"
          end
          "Available skills:\n#{items.join("\n")}"
        end

        private

        def scan_skills_dir(dir_path, source:, include_only: [], exclude: [])
          return unless File.directory?(dir_path)

          inc_patterns = Array(include_only).map { |p| Regexp.new(p) }
          exc_patterns = Array(exclude).map { |p| Regexp.new(p) }

          Dir.glob(File.join(dir_path, "*")).sort.each do |skill_dir|
            next unless File.directory?(skill_dir)

            base = File.basename(skill_dir)
            next if inc_patterns.any? && inc_patterns.none? { |r| r.match?(base) }
            next if exc_patterns.any? { |r| r.match?(base) }

            skill_file = File.join(skill_dir, "SKILL.md")
            next unless File.file?(skill_file)

            parsed = parse_skill_file(skill_file, skill_dir, source)
            @skills[parsed[:name]] = parsed if parsed
          end
        end

        def parse_skill_file(skill_file, skill_dir, source)
          content = File.read(skill_file, encoding: "UTF-8")
          # Load-bearing inside split: `name` comes out of that hash and the caller
          # drops the skill when it is empty, so a typo would silently unregister the
          # skill rather than report a broken one.
          parsed = Frontmatter.split(content, context: "antigravity.skills.frontmatter", skill_file:)
          return nil unless parsed

          meta, body = parsed
          name = meta["name"].to_s
          return nil if name.empty?

          { name:, description: meta["description"].to_s, body:, dir: skill_dir,
            skill_file:, source:, meta:, **resource_flags(skill_dir) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.skills.parse", skill_file:)
          nil
        end

        # Which optional subdirectories a skill ships, as the four keys the skill hash
        # carries. Progressive disclosure reads these to decide what to offer.
        def resource_flags(dir)
          %w[scripts references examples resources].to_h do |kind|
            [:"has_#{kind}", File.directory?(File.join(dir, kind))]
          end
        end

        def read_skill_body(skill)
          return skill[:body] unless skill[:body].to_s.empty?

          File.read(skill[:skill_file], encoding: "UTF-8")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.skills.read_body", skill_file: skill[:skill_file])
          skill[:description]
        end

        def load_usage
          return {} unless File.file?(@usage_file)

          data = YAML.safe_load(File.read(@usage_file), aliases: false)
          data.is_a?(Hash) ? data : {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.skills.load_usage",
                                        severity: :load_bearing, path: @usage_file)
          {}
        end

        def persist_usage
          FileUtils.mkdir_p(File.dirname(@usage_file))
          File.write(@usage_file, @usage.to_yaml)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.skills.persist_usage")
        end
      end
    end
  end
end
