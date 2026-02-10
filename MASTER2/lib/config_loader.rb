# frozen_string_literal: true

require "yaml"

module MASTER
  # ConfigLoader - Shared YAML config loading with mtime caching
  # Reduces repeated file reads and YAML parsing
  module ConfigLoader
    class << self
      def load(path, symbolize: true, default: nil)
        @cache ||= {}
        return default unless File.exist?(path)
        
        current_mtime = File.mtime(path)
        entry = @cache[path]
        return entry[:data] if entry && entry[:mtime] == current_mtime
        
        data = YAML.safe_load_file(path, symbolize_names: symbolize)
        @cache[path] = { data: data || default, mtime: current_mtime }
        data || default
      rescue StandardError => e
        $stderr.puts "MASTER: Failed to load #{path}: #{e.message}" if ENV["MASTER_DEBUG"]
        default
      end

      def invalidate(path = nil)
        path ? @cache&.delete(path) : @cache = {}
      end
    end
  end
end
