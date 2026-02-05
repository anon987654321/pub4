# frozen_string_literal: true

require 'yaml'

module MASTER
  class Principle
    # Phase 1: Use consolidated YAML data with backward compatibility
    CONSOLIDATED_PATH = File.join(MASTER::ROOT, 'data', 'principles.yml')
    
    @cache = nil
    @cache_mtime = nil
    @consolidated_cache = nil

    class << self
      def load_all
        # Try consolidated data first (Phase 1)
        if File.exist?(CONSOLIDATED_PATH)
          return load_from_consolidated
        end
        
        # Fallback to legacy individual YAML files
        load_from_individual_files
      end

      def load(name)
        # Try consolidated data first
        if File.exist?(CONSOLIDATED_PATH)
          data = load_consolidated_data
          principles = data['principles']
          if principles
            # Search by key or name
            principles.each do |key, principle|
              if key.to_s.include?(name) || principle['name']&.include?(name)
                return convert_to_legacy_format(principle, key)
              end
            end
          end
        end
        
        # Fallback to legacy individual files
        dir = Paths.principles
        path = Dir[File.join(dir, "*#{name}*.yml")].first
        return nil unless path && File.exist?(path)

        parse_file(path)
      end

      def anti_patterns
        load_all.flat_map { |p| p[:anti_patterns] || [] }
      end

      def clear_cache
        @cache = nil
        @cache_mtime = nil
        @consolidated_cache = nil
      end

      private

      def load_from_consolidated
        # Check cache based on file modification time
        current_mtime = File.mtime(CONSOLIDATED_PATH)
        if @cache && @cache_mtime == current_mtime
          return @cache
        end
        
        data = load_consolidated_data
        principles = data['principles']
        return [] unless principles
        
        @cache = principles.map do |key, principle|
          convert_to_legacy_format(principle, key)
        end
        @cache_mtime = current_mtime
        @cache
      end

      def load_consolidated_data
        @consolidated_cache ||= YAML.safe_load(
          File.read(CONSOLIDATED_PATH), 
          permitted_classes: [], 
          symbolize_names: false
        )
      end

      def convert_to_legacy_format(principle, key)
        # Support both string and symbol keys
        {
          name: principle['name'],
          description: principle['description'],
          tier: principle['tier'],
          priority: principle['priority'],
          auto_fixable: principle['auto_fixable'],
          anti_patterns: principle['anti_patterns'] || [],
          filename: "#{key}.yml"
        }
      end

      def load_from_individual_files
        dir = Paths.principles
        return [] unless Dir.exist?(dir)

        # Return cached if directory unchanged
        current_mtime = dir_mtime(dir)
        if @cache && @cache_mtime == current_mtime
          return @cache
        end

        @cache = Dir[File.join(dir, '*.yml')].sort.map do |path|
          parse_file(path)
        end
        @cache_mtime = current_mtime
        @cache
      end

      def dir_mtime(dir)
        Dir[File.join(dir, '*.yml')].map { |f| File.mtime(f) }.max
      end

      def parse_file(path)
        data = YAML.safe_load(File.read(path), permitted_classes: [], symbolize_names: true)
        data[:filename] = File.basename(path)
        data
      end
    end
  end
end
