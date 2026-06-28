# frozen_string_literal: true

require "fileutils"
require "yaml"

module Master
  module Now
    class Skills
      attr_reader :loaded

      def initialize(root:, event_bus: nil)
        @root   = root
        @bus    = event_bus
        @loaded = []
        @usage  = load_usage
      end

      def discover!
        @loaded = []
        seen = {}
        load_registry_skills(seen)
        skill_roots.each do |skills_path|
          Dir.children(skills_path).sort.each do |name|
            entry = File.join(skills_path, name)
            skill =
              if File.directory?(entry)
                load_skill_dir(entry, name)
              elsif name.end_with?(".md") && name != "README.md"
                load_skill_md_file(entry, File.basename(name, ".md"))
              end
            next unless skill
            next if seen[skill[:name].to_s]

            seen[skill[:name].to_s] = true
            @loaded << skill
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

      def load_registry_skills(seen)
        path = File.join(@root, "data", REGISTRY_PATH)
        return unless File.file?(path)

        data = Master.load_yaml(path)
        Array(data["skills"]).each do |row|
          next unless row.is_a?(Hash)

          name = row["name"].to_s
          next if name.empty? || seen[name]

          seen[name] = true
          @loaded << {
            name: name,
            description: row["description"].to_s,
            triggers: Array(row["triggers"]),
            body: row["body"].to_s,
            dir: File.join(@root, "data", SKILLS_DIR),
            has_ruby: false,
          }
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_registry", event_bus: @bus)
      end

      def skill_roots
        roots = [
          File.join(@root, "data", SKILLS_DIR),
          File.join(@root, SKILLS_DIR),
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

      SKILLS_DIR = "skills".freeze
      REGISTRY_PATH = "skills_registry.yml".freeze
    end
  end
end
