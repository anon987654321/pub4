# frozen_string_literal: true

module MASTER
  class Principle
    PRINCIPLES_DIR = File.join(__dir__, 'principles')

    class << self
      def load_all
        return [] unless Dir.exist?(PRINCIPLES_DIR)

        Dir[File.join(PRINCIPLES_DIR, '*.md')].sort.map do |path|
          parse(File.read(path), File.basename(path))
        end
      end

      def load(name)
        path = Dir[File.join(PRINCIPLES_DIR, "*#{name}*.md")].first
        return nil unless path && File.exist?(path)

        parse(File.read(path), File.basename(path))
      end

      private

      def parse(content, filename)
        lines = content.lines.map(&:chomp)
        name = lines.first&.sub(/^#\s*/, '') || filename.sub('.md', '')
        desc_line = lines.find { |l| l.start_with?('> ') }
        description = desc_line&.sub(/^>\s*/, '') || ''

        anti_patterns = []
        current_smell = nil

        lines.each do |line|
          if line.start_with?('### ')
            current_smell = { name: line.sub('### ', ''), examples: [], fixes: [] }
            anti_patterns << current_smell
          elsif current_smell
            if line.include?('**Example')
              current_smell[:examples] << line.sub(/\*\*Example.*?\*\*:?\s*/, '')
            elsif line.include?('**Fix')
              current_smell[:fixes] << line.sub(/\*\*Fix.*?\*\*:?\s*/, '')
            end
          end
        end

        {
          name: name,
          description: description,
          anti_patterns: anti_patterns,
          filename: filename
        }
      end
    end
  end
end
