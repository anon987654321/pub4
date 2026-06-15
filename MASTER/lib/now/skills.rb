# frozen_string_literal: true

require "fileutils"
require "yaml"

module Master
  module Now
    class Skills
      SKILLS_DIR = "skills".freeze

      attr_reader :loaded

      def initialize(root:, event_bus: nil)
        @root   = root
        @bus    = event_bus
        @loaded = []
        @usage  = load_usage
      end

      def discover!
        @loaded = []
        skill_roots.each do |skills_path|
          Dir.children(skills_path).sort.each do |name|
            entry = File.join(skills_path, name)
            skill =
              if File.directory?(entry)
                load_skill_dir(entry, name)
              elsif name.end_with?(".md") && name != "README.md"
                load_skill_md_file(entry, File.basename(name, ".md"))
              end
            @loaded << skill if skill
          end
        end

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

      def record_used(name)
        @usage[name.to_s] = Time.now.to_i
        persist_usage
      end

      private

      def skill_roots
        roots = [
          File.join(@root, "data", SKILLS_DIR),
          File.join(@root, SKILLS_DIR)
        ]
        roots.select { |path| Dir.exist?(path) }.uniq
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

      def load_skill_dir(dir, name)
        md_path = File.join(dir, "SKILL.md")
        rb_path = File.join(dir, "skill.rb")

        metadata = parse_skill_md(md_path) if File.exist?(md_path)
        metadata ||= { "name" => name, "description" => name }

        skill = {
          name: metadata["name"] || name,
          description: metadata["description"] || name,
          triggers: metadata["triggers"] || [],
          dir: dir,
          has_ruby: File.exist?(rb_path),
        }

        if File.exist?(rb_path)
          begin
            require rb_path
            @bus&.publish("skills:ruby_loaded", skill: name)
          rescue StandardError => e
            @bus&.publish("skills:load_error", skill: name, error: e.message)
          end
        end

        skill
        rescue StandardError => e
        @bus&.publish("skills:load_error", skill: name, error: e.message)
        nil
      end

      def load_skill_md_file(path, name)
        metadata = parse_skill_md(path)
        metadata ||= { "name" => name, "description" => name }

        {
          name: metadata["name"] || name,
          description: metadata["description"] || name,
          triggers: metadata["triggers"] || [],
          dir: File.dirname(path),
          has_ruby: false,
        }
      rescue StandardError => e
        @bus&.publish("skills:load_error", skill: name, error: e.message)
        nil
      end

      def parse_skill_md(path)
        Master::Ground::Frontmatter.parse_file(path)[:meta]
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.parse_frontmatter", event_bus: @bus)
        {}
      end
    end
  end
end
