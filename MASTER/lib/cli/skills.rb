# frozen_string_literal: true

require "fileutils"
require "yaml"

module Master
  module CLI
    class Skills
      attr_reader :loaded

      def initialize(root:, event_bus: nil)
        @root = root
        @bus = event_bus
        @loaded = []
        @usage = load_usage
      end

      def discover!
        @loaded = []
        load_antigravity_skills
        load_directory_skills
        load_registry_skills({})
        @loaded = sort_by_recency(@loaded)
        @bus&.publish("skills:loaded", count: @loaded.size)
        @loaded
      end

      def list
        return "(no skills loaded)" if @loaded.empty?

        @loaded.map { |s| "#{s[:name]}: #{s[:description]}" }.join("\n")
      end

      def find(name)
        @loaded.find { |s| s[:name] == name.to_s }
      end

      def trigger_for(input)
        matches = @loaded.select do |s|
          s[:triggers]&.any? { |t| input.match?(Regexp.new(t, Regexp::IGNORECASE)) }
        end
        matches.each { |skill| record_used(skill[:name]) }
        matches
      end

      def body_for(name)
        skill = find(name)
        return unless skill

        body = skill[:body].to_s.strip
        return body[0, 4_000] unless body.empty?

        md_path = File.join(skill[:dir], "SKILL.md")
        return skill[:description].to_s unless File.file?(md_path)

        File.read(md_path, encoding: "UTF-8")[0, 4_000]
      rescue StandardError => e
        Ground::Swallow.log(e, context: "skills.body_for", event_bus: @bus)
        skill[:description].to_s
      end

      def record_used(name)
        @usage[name.to_s] = Time.now.to_i
        persist_usage
      end

      private

      def load_antigravity_skills
        require_relative "../ground/antigravity"
        discovery = Master::Ground::Antigravity::Discovery.new(cwd: @root, workspace_root: @root)
        roots = discovery.workspace_customization_roots
        declared = discovery.declared_skills_entries
        return if roots.empty? && declared.empty? && @root != Master::ROOT

        coordinator = Master::Ground::Antigravity::Coordinator.new(cwd: @root, workspace_root: @root)
        coordinator.skills.discover!.each do |skill|
          next if find(skill[:name])

          @loaded << {
            name: skill[:name],
            description: skill[:description],
            triggers: Array(skill.dig(:meta, "triggers")),
            body: skill[:body],
            dir: skill[:dir],
            has_ruby: Dir.glob(File.join(skill[:dir], "*.rb")).any?,
            source: skill[:source],
          }
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_antigravity", event_bus: @bus)
      end

      def load_registry_skills(_seen)
        path = File.join(@root, "data", REGISTRY_PATH)
        return unless File.file?(path)

        data = (Master.load_yaml(path) || {})["skills_registry"] || {}
        Array(data["skills"]).each do |row|
          skill = registry_skill(row)
          @loaded << skill if skill
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_registry", event_bus: @bus)
      end

      def load_directory_skills
        pattern = File.join(@root, "data", SKILLS_DIR, "*", "SKILL.md")
        Dir.glob(pattern).sort.each { |path| load_skill_file(path) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_directory", event_bus: @bus)
      end

      def load_skill_file(path)
        metadata, body = parse_skill_file(path)
        name = metadata["name"].to_s
        return if name.empty? || find(name)

        @loaded << {
          name:,
          description: metadata["description"].to_s,
          triggers: Array(metadata["triggers"]),
          body:,
          dir: File.dirname(path),
          has_ruby: Dir.glob(File.join(File.dirname(path), "*.rb")).any?,
        }
      rescue Psych::Exception, Errno::EACCES => e
        Master::Ground::Swallow.log(e, context: "skills.load_file", event_bus: @bus, path:)
      end

      def registry_skill(row)
        return unless row.is_a?(Hash)

        name = row["name"].to_s
        return if name.empty? || find(name)

        {
          name:,
          description: row["description"].to_s,
          triggers: Array(row["triggers"]),
          body: row["body"].to_s,
          dir: File.join(@root, "data", SKILLS_DIR),
          has_ruby: false,
        }
      end

      def parse_skill_file(path)
        source = File.read(path, encoding: "UTF-8")
        match = source.match(/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m)
        return [{}, ""] unless match

        [YAML.safe_load(match[1], aliases: false) || {}, match[2].to_s.strip]
      end

      def sort_by_recency(skills)
        skills.sort_by { |skill| [-@usage.fetch(skill[:name].to_s, 0).to_i, skill[:name].to_s] }
      end

      def usage_path
        File.join(@root, "runtime", "skill_usage.yml")
      end

      def load_usage
        return {} unless File.exist?(usage_path)

        data = Master.load_yaml(usage_path)
        data.is_a?(Hash) ? data : {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_usage", event_bus: @bus)
        {}
      end

      def persist_usage
        FileUtils.mkdir_p(File.dirname(usage_path))
        File.write(usage_path, @usage.to_yaml)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.persist_usage", event_bus: @bus)
      end

      SKILLS_DIR = "skills".freeze
      REGISTRY_PATH = "patterns.yml".freeze
    end
  end
end
