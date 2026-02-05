# frozen_string_literal: true

require 'yaml'

module MASTER
  class Principle
    @cache = nil
    @cache_mtime = nil

    class << self
      def load_all
        dir = Paths.principles
        return [] unless Dir.exist?(dir)

        # Return cached if directory unchanged
        current_mtime = dir_mtime(dir)
        if @cache && @cache_mtime == current_mtime
          return @cache
        end

        @cache = Dir[File.join(dir, '*.yml')].sort.map do |path|
          parse(path)
        end
        @cache_mtime = current_mtime
        @cache
      end

      def load(name)
        dir = Paths.principles
        path = Dir[File.join(dir, "*#{name}*.yml")].first
        return nil unless path && File.exist?(path)

        parse(path)
      end

      def anti_patterns
        load_all.flat_map { |p| p[:anti_patterns] || [] }
      end

      def clear_cache
        @cache = nil
        @cache_mtime = nil
      end

      private

      def dir_mtime(dir)
        Dir[File.join(dir, '*.yml')].map { |f| File.mtime(f) }.max
      end

      def parse(path)
        data = YAML.safe_load(File.read(path), permitted_classes: [], symbolize_names: true)
        data[:filename] = File.basename(path)
        data
      end
    end
  end
end
