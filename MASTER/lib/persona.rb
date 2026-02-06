# frozen_string_literal: true

require 'yaml'

module MASTER
  class Persona
    # Phase 1: Use consolidated YAML data with backward compatibility
    CONSOLIDATED_PATH = File.join(MASTER::ROOT, 'data', 'personas.yml')
    
    class << self
      def load_all
        # Try consolidated data first (Phase 1)
        if File.exist?(CONSOLIDATED_PATH)
          return load_from_consolidated
        end
        
        # Fallback to legacy markdown files
        load_from_markdown
      end

      def load(name)
        # Try consolidated data first
        if File.exist?(CONSOLIDATED_PATH)
          data = load_consolidated_data
          persona = data.dig('personas', name) || data.dig('personas', name.to_s)
          return convert_to_legacy_format(persona) if persona
        end
        
        # Fallback to legacy markdown
        load_from_markdown_file(name)
      end

      def list
        # Try consolidated data first
        if File.exist?(CONSOLIDATED_PATH)
          data = load_consolidated_data
          personas = data['personas']
          return personas.keys.map(&:to_s).sort if personas
        end
        
        # Fallback to legacy markdown
        dir = Paths.personas
        return [] unless Dir.exist?(dir)

        Dir[File.join(dir, '*.md')].map do |path|
          File.basename(path, '.md')
        end.sort
      end

      private

      def load_from_consolidated
        data = load_consolidated_data
        personas = data['personas']
        return [] unless personas
        
        personas.map do |key, persona|
          convert_to_legacy_format(persona)
        end
      end

      def load_consolidated_data
        @consolidated_cache ||= YAML.safe_load(
          File.read(CONSOLIDATED_PATH), 
          permitted_classes: [], 
          symbolize_names: false
        )
      end

      def convert_to_legacy_format(persona)
        {
          name: persona['name'],
          traits: persona['traits']&.join(', '),
          style: persona['style'],
          focus: persona['focus']&.join(', '),
          sources: persona['sources']&.join(', '),
          rules: persona['rules'],
          prompt: persona['system_prompt']
        }
      end

      def load_from_markdown
        dir = Paths.personas
        return [] unless Dir.exist?(dir)

        Dir[File.join(dir, '*.md')].map do |path|
          parse(File.read(path), File.basename(path, '.md'))
        end
      end

      def load_from_markdown_file(name)
        path = File.join(Paths.personas, "#{name}.md")
        return nil unless File.exist?(path)

        parse(File.read(path), name)
      end

      def parse(content, name)
        sections = {}
        current = nil

        content.lines.each do |line|
          line = line.chomp
          if line.start_with?('## ')
            current = line.sub('## ', '').downcase.to_sym
            sections[current] = []
          elsif current && !line.empty?
            sections[current] << line.sub(/^[-*]\s*/, '')
          end
        end

        {
          name: name,
          traits: sections[:traits]&.join(', '),
          style: sections[:style]&.first,
          focus: sections[:focus]&.join(', '),
          sources: sections[:sources]&.join(', '),
          rules: sections[:rules],
          prompt: build_prompt(name, sections)
        }
      end

      def build_prompt(name, sections)
        parts = ["You are #{name}."]
        parts << "Traits: #{sections[:traits]&.join(', ')}" if sections[:traits]
        parts << "Style: #{sections[:style]&.first}" if sections[:style]
        parts << "Focus: #{sections[:focus]&.join(', ')}" if sections[:focus]
        parts.join(' ')
      end
      
      # Clear cache (for testing)
      def clear_cache
        @consolidated_cache = nil
      end
    end
  end
end
