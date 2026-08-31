# frozen_string_literal: true

require "pathname"
require "yaml"
require "fileutils"
require_relative "discovery"

module Master
  module Ground
    module Antigravity
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
        rescue StandardError
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
