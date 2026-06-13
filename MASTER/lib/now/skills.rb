# frozen_string_literal: true

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
      end

      def discover!
        skills_path = File.join(@root, SKILLS_DIR)
        return [] unless Dir.exist?(skills_path)

        Dir.children(skills_path).sort.each do |name|
          dir = File.join(skills_path, name)
          next unless File.directory?(dir)

          skill = load_skill(dir, name)
          @loaded << skill if skill
        end

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
        @loaded.select do |s|
          s[:triggers]&.any? { |t| input.match?(Regexp.new(t, Regexp::IGNORECASE)) }
        end
      end

      private

      def load_skill(dir, name)
        md_path = File.join(dir, "SKILL.md")
        rb_path = File.join(dir, "skill.rb")

        metadata = parse_skill_md(md_path) if File.exist?(md_path)
        metadata ||= { "name" => name, "description" => name }

        skill = {
          name: metadata["name"] || name,
          description: metadata["description"] || name,
          triggers: metadata["triggers"] || [],
          dir: dir,
          has_ruby: File.exist?(rb_path)
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

      def parse_skill_md(path)
        Master::Ground::Frontmatter.parse_file(path)[:meta]
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.parse_frontmatter", event_bus: @bus)
        {}
      end
    end
  end
end
