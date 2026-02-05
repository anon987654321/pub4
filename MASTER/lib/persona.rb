# frozen_string_literal: true

module MASTER
  class Persona
    class << self
      def load_all
        dir = Paths.personas
        return [] unless Dir.exist?(dir)

        Dir[File.join(dir, '*.md')].map do |path|
          parse(File.read(path), File.basename(path, '.md'))
        end
      end

      def load(name)
        path = File.join(Paths.personas, "#{name}.md")
        return nil unless File.exist?(path)

        parse(File.read(path), name)
      end

      def list
        dir = Paths.personas
        return [] unless Dir.exist?(dir)

        Dir[File.join(dir, '*.md')].map do |path|
          File.basename(path, '.md')
        end.sort
      end

      private

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
    end
  end
end
